# SPDX-FileCopyrightText: 2026 James Harton
#
# SPDX-License-Identifier: Apache-2.0

defmodule BB.MCP.Tools do
  @moduledoc """
  Shared logic used by the per-tool component modules under
  `BB.MCP.Tools.*`.

  Tools take a `robot` argument that selects which configured robot module
  they operate on. The list of configured robots is read from
  `Application.get_env(:bb_mcp, :robots, [])`.
  """

  alias Anubis.MCP.Error
  alias BB.MCP.Robots

  @doc """
  Read the configured robots map.
  """
  @spec robots() :: Robots.config()
  def robots do
    :bb_mcp
    |> Application.get_env(:robots, [])
    |> Robots.build!()
  end

  @doc """
  Resolve a `robot` argument from tool params to a robot module.

  Returns `{:ok, module}` or `{:error, Anubis.MCP.Error.t()}`.
  """
  @spec fetch_robot(map()) :: {:ok, module()} | {:error, struct()}
  def fetch_robot(params) when is_map(params) do
    case get_arg(params, :robot) do
      name when is_binary(name) ->
        case Robots.fetch(robots(), name) do
          {:ok, module} ->
            {:ok, module}

          {:error, :unknown_robot} ->
            {:error,
             Error.protocol(:invalid_request, %{
               message: "unknown robot #{inspect(name)}; available: #{available_names()}"
             })}
        end

      _other ->
        {:error,
         Error.protocol(:invalid_request, %{
           message: "missing required argument: robot (one of: #{available_names()})"
         })}
    end
  end

  def fetch_robot(_params) do
    {:error,
     Error.protocol(:invalid_request, %{
       message: "missing required argument: robot (one of: #{available_names()})"
     })}
  end

  @doc """
  Fetch a tool argument from string-keyed or atom-keyed params.
  """
  @spec get_arg(map(), atom()) :: term()
  def get_arg(params, key) when is_map(params) and is_atom(key) do
    Map.get(params, Atom.to_string(key), Map.get(params, key))
  end

  @doc """
  Comma-separated list of configured robot names, for error messages.
  """
  @spec available_names() :: String.t()
  def available_names do
    case robots() do
      empty when empty == %{} -> "(none configured)"
      map -> map |> Map.keys() |> Enum.sort() |> Enum.join(", ")
    end
  end

  @doc """
  Schema fragment for the `robot` argument, shared by every tool.
  """
  @spec robot_arg_schema() :: map()
  def robot_arg_schema do
    %{
      "type" => "string",
      "description" =>
        "Name of the robot to operate on. Use the list_robots tool to see " <>
          "configured robots."
    }
  end

  @doc """
  Parse a parameter path string (`"motion.max_speed"`) into atoms.
  """
  @spec parse_path(String.t()) :: [atom()]
  def parse_path(path) when is_binary(path) do
    path
    |> String.split(".", trim: true)
    |> Enum.map(&String.to_atom/1)
  end

  @splode_internal_fields [:splode, :bread_crumbs, :vars, :path, :stacktrace]

  @doc """
  Convert any failure value into an `Anubis.MCP.Error` for the JSON-RPC reply.

  `BB.Error` (Splode) exceptions are rendered via `Exception.message/1` with
  their user-declared fields exposed under `data`, so MCP clients see the
  actual reason (e.g. "Robot is in state `:armed`, requires one of: `:disarmed`")
  instead of a generic "Internal error". Anubis errors pass through unchanged.
  """
  @spec to_anubis_error(term()) :: Anubis.MCP.Error.t()
  def to_anubis_error(%Error{} = error), do: error

  def to_anubis_error(%module{} = error) do
    if is_exception(error) do
      Error.execution(Exception.message(error), exception_data(error, module))
    else
      Error.execution(inspect(error))
    end
  end

  def to_anubis_error(reason), do: Error.execution(inspect(reason))

  defp exception_data(error, module) do
    error
    |> Map.from_struct()
    |> Map.drop(@splode_internal_fields)
    |> Enum.reject(fn {_k, v} -> is_nil(v) or v == [] end)
    |> Map.new(fn {k, v} -> {k, jsonable(v)} end)
    |> Map.put(:error_type, inspect(module))
  end

  defp jsonable(nil), do: nil
  defp jsonable(atom) when is_atom(atom) and not is_boolean(atom), do: inspect(atom)
  defp jsonable(list) when is_list(list), do: Enum.map(list, &jsonable/1)
  defp jsonable(tuple) when is_tuple(tuple), do: tuple |> Tuple.to_list() |> jsonable()
  defp jsonable(other), do: other
end
