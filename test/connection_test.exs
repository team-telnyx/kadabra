defmodule Kadabra.ConnectionTest do
  use ExUnit.Case

  test "closes active streams on socket close" do
    uri = ~c"https://http2.codedge.dev"
    {:ok, pid} = Kadabra.open(uri)

    ref = Process.monitor(pid)

    # Open two streams that send the time every second
    Kadabra.get(pid, "/clockstream", on_response: & &1)
    Kadabra.get(pid, "/clockstream", on_response: & &1)

    conn_pid = :sys.get_state(pid).connection
    socket_pid = :sys.get_state(conn_pid).config.socket

    # Wait to collect some data on the streams
    Process.sleep(500)

    state = :sys.get_state(conn_pid)
    assert Enum.count(state.flow_control.stream_set.active_streams) == 2

    # frame = Kadabra.Frame.Goaway.new(1)
    # GenServer.cast(conn_pid, {:recv, frame})
    send(socket_pid, {:ssl_closed, nil})

    assert_receive {:closed, ^pid}, 5_000
    assert_receive {:DOWN, ^ref, :process, ^pid, :shutdown}, 5_000
  end

  test "a socket start failure preserves the real connect reason (no MatchError)" do
    Process.flag(:trap_exit, true)

    # `bad scheme` makes Kadabra.Socket.connect/2 return {:error, :bad_scheme},
    # standing in for the incident's {:error, {:tls_alert, {:certificate_expired, _}}}.
    config = %Kadabra.Config{
      uri: URI.parse("ftp://example.com"),
      opts: [],
      client: self(),
      queue: self()
    }

    assert {:error, {:shutdown, :bad_scheme}} = Kadabra.Connection.start_link(config)
  end
end
