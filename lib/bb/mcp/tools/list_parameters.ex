# SPDX-FileCopyrightText: 2026 James Harton
#
# SPDX-License-Identifier: Apache-2.0

defmodule BB.MCP.Tools.ListParameters do
  @moduledoc """
  List the runtime parameters registered on a robot, optionally filtered
  by a path prefix.

  Returns each parameter's dotted path and current value.
  """

  use Anubis.Server.Component, type: :tool

  alias Anubis.Server.Response
  alias BB.MCP.Tools
  alias BB.Parameter

  schema do
    field(:robot, :string, required: true)

    field(:prefix, :string,
      required: false,
      description: "Dotted path prefix to filter by (e.g. \"controller.pid\")"
    )
  end

  @impl true
  def execute(params, frame) do
    case Tools.fetch_robot(params) do
      {:ok, robot} ->
        prefix =
          case Tools.get_arg(params, :prefix) do
            nil -> []
            "" -> []
            str -> Tools.parse_path(str)
          end

        payload =
          robot
          |> Parameter.list(prefix: prefix)
          |> Enum.map(&format_parameter/1)

        {:reply, Response.json(Response.tool(), %{"parameters" => payload}), frame}

      {:error, error} ->
        {:error, error, frame}
    end
  end

  defp format_parameter({path, metadata}) when is_map(metadata) do
    Map.reject(
      %{
        "path" => format_path(path),
        "value" => Map.get(metadata, :value),
        "type" => metadata |> Map.get(:type) |> inspect_or_nil(),
        "doc" => Map.get(metadata, :doc),
        "default" => Map.get(metadata, :default)
      },
      fn {_k, v} -> is_nil(v) end
    )
  end

  defp format_parameter({path, value}) do
    %{"path" => format_path(path), "value" => value}
  end

  defp format_path(path), do: Enum.map_join(path, ".", &Atom.to_string/1)

  defp inspect_or_nil(nil), do: nil
  defp inspect_or_nil(other), do: inspect(other)
end
