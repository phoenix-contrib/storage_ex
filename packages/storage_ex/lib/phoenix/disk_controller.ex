defmodule StorageEx.Phoenix.DiskController do
  @moduledoc """
  Controller for serving files from disk storage with signed URLs.

  Handles:
  - GET requests to download files via signed tokens
  - PUT requests to upload files via signed tokens (direct uploads)

  Similar to Rails' ActiveStorage::DiskController.
  """

  import Plug.Conn

  @doc """
  Initializes the controller action.
  """
  def init(action), do: action

  @doc """
  Callback required by Phoenix controllers.
  """
  def call(conn, action) do
    apply(__MODULE__, action, [conn, conn.params])
  end

  @doc """
  Downloads a file using a signed token.

  Verifies the token, retrieves the file from disk, and streams it to the client
  with appropriate headers for content type and disposition.
  """
  def show(conn, %{"encoded_key" => encoded_key, "filename" => filename}) do
    case decode_verified_key(conn, encoded_key) do
      {:ok, key_data} ->
        service = StorageEx.Config.get_service!(key_data.service_name)
        path = StorageEx.Services.DiskService.path_for(service, key_data.key)

        case File.stat(path) do
          {:ok, %{type: :regular}} ->
            conn
            |> put_resp_header(
              "content-type",
              key_data.content_type || "application/octet-stream"
            )
            |> put_resp_header(
              "content-disposition",
              content_disposition(key_data.disposition, filename)
            )
            |> send_file(200, path)

          _ ->
            send_resp(conn, 404, "Not Found")
        end

      {:error, _reason} ->
        send_resp(conn, 404, "Not Found")
    end
  end

  @doc """
  Uploads a file using a signed token for direct uploads.

  Verifies the token, checks content type and length match expectations,
  then saves the file to disk with optional checksum verification.
  """
  def update(conn, %{"encoded_token" => encoded_token}) do
    case decode_verified_token(conn, encoded_token) do
      {:ok, token_data} ->
        if acceptable_content?(conn, token_data) do
          service = StorageEx.Config.get_service!(token_data.service_name)
          {:ok, body, conn} = read_body(conn)

          case StorageEx.Services.DiskService.upload(service, token_data.key, body,
                 checksum: token_data[:checksum]
               ) do
            {:ok, _key} ->
              send_resp(conn, 204, "")

            {:error, :integrity_error} ->
              send_resp(conn, 422, "Integrity check failed")

            {:error, _reason} ->
              send_resp(conn, 422, "Upload failed")
          end
        else
          send_resp(conn, 422, "Content type or length mismatch")
        end

      {:error, _reason} ->
        send_resp(conn, 404, "Not Found")
    end
  end

  # Private helpers

  defp decode_verified_key(conn, encoded_key) do
    salt = get_token_salt(conn)

    case Phoenix.Token.verify(conn, salt, encoded_key, max_age: :infinity) do
      {:ok, data} when is_map(data) ->
        {:ok, data}

      _ ->
        {:error, :invalid_token}
    end
  end

  defp decode_verified_token(conn, encoded_token) do
    salt = get_token_salt(conn)

    case Phoenix.Token.verify(conn, salt, encoded_token, max_age: :infinity) do
      {:ok, data} when is_map(data) ->
        {:ok, data}

      _ ->
        {:error, :invalid_token}
    end
  end

  defp acceptable_content?(conn, token_data) do
    content_type_matches?(conn, token_data[:content_type]) and
      content_length_matches?(conn, token_data[:content_length])
  end

  defp content_type_matches?(_conn, nil), do: true

  defp content_type_matches?(conn, expected_type) do
    case get_req_header(conn, "content-type") do
      [content_type | _] -> content_type == expected_type
      _ -> false
    end
  end

  defp content_length_matches?(_conn, nil), do: true

  defp content_length_matches?(conn, expected_length) do
    case get_req_header(conn, "content-length") do
      [content_length | _] ->
        case Integer.parse(content_length) do
          {length, ""} -> length == expected_length
          _ -> false
        end

      _ ->
        false
    end
  end

  defp content_disposition(:inline, filename), do: "inline; filename=\"#{filename}\""
  defp content_disposition(:attachment, filename), do: "attachment; filename=\"#{filename}\""
  defp content_disposition(_, filename), do: "inline; filename=\"#{filename}\""

  defp get_token_salt(conn) do
    conn.private[:storage_ex_token_salt] ||
      Application.get_env(:storage_ex, :token_salt, "storage_ex_disk_service")
  end
end
