defmodule Kadabra.SocketTest do
  use ExUnit.Case, async: true

  alias Kadabra.Socket

  describe "options/2 for :https" do
    setup do
      {:ok, opts: Socket.options([], :https)}
    end

    test "verifies the peer against a CA bundle", %{opts: opts} do
      assert Keyword.get(opts, :verify) == :verify_peer
      assert Keyword.has_key?(opts, :cacerts)
    end

    test "advertises h2 over ALPN", %{opts: opts} do
      assert Keyword.get(opts, :alpn_advertised_protocols) == [<<"h2">>]
    end

    test "uses the HTTPS (RFC 6125) hostname match fun", %{opts: opts} do
      check = Keyword.fetch!(opts, :customize_hostname_check)
      match_fun = Keyword.fetch!(check, :match_fun)
      assert is_function(match_fun, 2)

      # Regression: a wildcard SAN must match a single left-most label.
      # fcm.googleapis.com is now served under a *.googleapis.com-only cert;
      # without this match fun, verify_peer rejects it with
      # {:bad_cert, :hostname_check_failed} and FCM pushes fail to connect.
      assert match_fun.(
               {:dns_id, ~c"fcm.googleapis.com"},
               {:dNSName, ~c"*.googleapis.com"}
             )

      # An exact SAN still matches.
      assert match_fun.(
               {:dns_id, ~c"fcm.googleapis.com"},
               {:dNSName, ~c"fcm.googleapis.com"}
             )

      # A wildcard must not span multiple labels, and unrelated names must not match.
      refute match_fun.(
               {:dns_id, ~c"a.b.googleapis.com"},
               {:dNSName, ~c"*.googleapis.com"}
             )

      refute match_fun.(
               {:dns_id, ~c"evil.com"},
               {:dNSName, ~c"*.googleapis.com"}
             )
    end

    test "prepends caller-supplied opts", %{opts: _opts} do
      opts =
        Socket.options([{:server_name_indication, ~c"example.com"}], :https)

      assert Keyword.get(opts, :server_name_indication) == ~c"example.com"
      # defaults are still present alongside the caller opts
      assert Keyword.get(opts, :verify) == :verify_peer
    end
  end

  test "options/2 for :http carries no TLS options" do
    opts = Socket.options([], :http)
    refute Keyword.has_key?(opts, :verify)
    refute Keyword.has_key?(opts, :customize_hostname_check)
    refute Keyword.has_key?(opts, :cacerts)
  end

  describe "connect_timeout/1" do
    test "defaults to :infinity" do
      assert Socket.connect_timeout([]) == :infinity
      assert Socket.connect_timeout(ssl: []) == :infinity
    end

    test "accepts milliseconds or :infinity" do
      assert Socket.connect_timeout(connect_timeout: 5_000) == 5_000
      assert Socket.connect_timeout(connect_timeout: :infinity) == :infinity
    end

    test "rejects anything else" do
      assert_raise ArgumentError, fn ->
        Socket.connect_timeout(connect_timeout: -1)
      end

      assert_raise ArgumentError, fn ->
        Socket.connect_timeout(connect_timeout: "5s")
      end
    end
  end

  describe "start_link/2 with :connect_timeout" do
    test "returns {:error, :timeout} when the TLS handshake never completes" do
      # A listener that accepts the TCP connection but never speaks TLS, so
      # :ssl.connect/4 blocks in the handshake until the timeout fires.
      {:ok, listen} =
        :gen_tcp.listen(0, [:binary, active: false, reuseaddr: true])

      {:ok, port} = :inet.port(listen)
      uri = URI.parse("https://127.0.0.1:#{port}")

      # The socket is linked to the caller and exits with the connect reason.
      Process.flag(:trap_exit, true)

      {elapsed_us, result} =
        :timer.tc(fn ->
          Socket.start_link(uri,
            ssl: [verify: :verify_none],
            connect_timeout: 200
          )
        end)

      assert {:error, :timeout} = result
      assert elapsed_us < 2_000_000

      :gen_tcp.close(listen)
    end
  end
end
