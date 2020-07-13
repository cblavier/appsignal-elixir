defmodule Appsignal.Transmitter do
  @moduledoc false
  require Logger

  def request(method, url, headers \\ [], body \\ "") do
    http_client = Application.get_env(:appsignal, :http_client, :hackney)
    :application.ensure_all_started(http_client)

    http_client.request(method, url, headers, body, options())
  end

  defp options do
    ca_file_path = Appsignal.Config.ca_file_path()

    options =
      case File.stat(ca_file_path) do
        {:ok, %{access: access}} when access in [:read, :read_write] ->
          {:ok,
           [
             ssl_options:
               [
                 verify: :verify_peer,
                 cacertfile: ca_file_path,
                 depth: 4,
                 ciphers: ciphers(),
                 honor_cipher_order: :undefined
               ] ++ customize_hostname_check_or_verify_fun()
           ]}

        {:ok, %{access: access}} ->
          {:error, "File access is #{inspect(access)}"}

        {:error, reason} ->
          {:error, reason}
      end

    case options do
      {:ok, options} ->
        options

      {:error, message} ->
        unless ca_file_path == packaged_ca_file_path() do
          Logger.warn(
            "Ignoring non-existing or unreadable ca_file_path (#{ca_file_path}): #{
              inspect(message)
            }"
          )
        end

        []
    end
  end

  defp packaged_ca_file_path do
    Path.join(:code.priv_dir(:appsignal), "cacert.pem")
  end

  cond do
    System.otp_release() >= "23" ->
      defp ciphers, do: :ssl.cipher_suites(:default, :"tlsv1.3")

    System.otp_release() >= "20.3" ->
      defp ciphers, do: :ssl.cipher_suites(:default, :"tlsv1.2")

    true ->
      defp ciphers, do: :ssl.cipher_suites()
  end

  if System.otp_release() >= "21" do
    defp customize_hostname_check_or_verify_fun do
      [
        customize_hostname_check: [
          match_fun: :public_key.pkix_verify_hostname_match_fun(:https)
        ]
      ]
    end
  else
    defp customize_hostname_check_or_verify_fun do
      [
        verify_fun:
          {fn
             _, :valid, state -> {:valid, state}
             _, :valid_peer, state -> {:valid, state}
             _, {:extension, _}, state -> {:unknown, state}
             _, reason, _ -> {:fail, reason}
           end, self()}
      ]
    end
  end
end
