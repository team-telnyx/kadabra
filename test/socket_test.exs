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
      assert match_fun.({:dns_id, ~c"fcm.googleapis.com"}, {:dNSName, ~c"*.googleapis.com"})

      # An exact SAN still matches.
      assert match_fun.({:dns_id, ~c"fcm.googleapis.com"}, {:dNSName, ~c"fcm.googleapis.com"})

      # A wildcard must not span multiple labels, and unrelated names must not match.
      refute match_fun.({:dns_id, ~c"a.b.googleapis.com"}, {:dNSName, ~c"*.googleapis.com"})
      refute match_fun.({:dns_id, ~c"evil.com"}, {:dNSName, ~c"*.googleapis.com"})
    end

    test "prepends caller-supplied opts", %{opts: _opts} do
      opts = Socket.options([{:server_name_indication, ~c"example.com"}], :https)
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
end
