defmodule Polticool.LegiScan do
  @moduledoc """
  Minimal Req client for the LegiScan API (https://legiscan.com/legiscan, CC BY 4.0).

  Config: `config :polticool, Polticool.LegiScan, api_key:, base_url:, req_options:`
  (`LEGISCAN_API_KEY` in runtime.exs; tests inject `plug: {Req.Test, Polticool.LegiScan}`).
  The free tier allows 10,000 queries a month, so use `dataset_list/1` (1 query) and
  download a dataset only when its hash changed.
  """

  @default_url "https://api.legiscan.com/"

  @doc "Lists dataset metadata for a state, e.g. `dataset_list(\"UT\")`."
  def dataset_list(state) do
    with {:ok, body} <- call("getDatasetList", state: state) do
      {:ok, Map.get(body, "datasetlist", [])}
    end
  end

  @doc "Downloads a dataset and returns `{:ok, zip_binary}`."
  def get_dataset(session_id, access_key) do
    with {:ok, %{"dataset" => %{"zip" => b64}}} <-
           call("getDataset", id: session_id, access_key: access_key),
         {:ok, zip} <- Base.decode64(b64, ignore: :whitespace) do
      {:ok, zip}
    else
      {:ok, _} -> {:error, :unexpected_response}
      :error -> {:error, :invalid_base64}
      {:error, _} = err -> err
    end
  end

  defp call(op, params) do
    case config(:api_key, nil) do
      nil ->
        {:error, :missing_api_key}

      key ->
        req =
          Req.new(
            [
              base_url: config(:base_url, @default_url),
              params: [key: key, op: op] ++ params,
              receive_timeout: 120_000
            ] ++ config(:req_options, [])
          )

        case Req.get(req) do
          {:ok, %Req.Response{status: 200, body: %{"status" => "OK"} = body}} ->
            {:ok, body}

          {:ok, %Req.Response{status: 200, body: %{"status" => "ERROR", "alert" => alert}}} ->
            {:error, {:api, alert["message"]}}

          {:ok, %Req.Response{status: status, body: body}} ->
            {:error, {:http, status, body}}

          {:error, reason} ->
            {:error, reason}
        end
    end
  end

  defp config(key, default),
    do: :polticool |> Application.get_env(__MODULE__, []) |> Keyword.get(key, default)
end
