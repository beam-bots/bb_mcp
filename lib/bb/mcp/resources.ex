# SPDX-FileCopyrightText: 2026 James Harton
#
# SPDX-License-Identifier: Apache-2.0

defmodule BB.MCP.Resources do
  @moduledoc """
  Shared helpers for the resource component modules under
  `BB.MCP.Resources.*`.
  """

  alias Anubis.MCP.Error
  alias BB.MCP.Robots
  alias BB.MCP.Tools

  @doc """
  Resolve a `robot` URI template variable to a robot module.

  Returns `{:ok, module}` or `{:error, Anubis.MCP.Error.t()}`.
  """
  @spec fetch_robot(map()) :: {:ok, module()} | {:error, struct()}
  def fetch_robot(%{"params" => %{"robot" => name}}) when is_binary(name) do
    case Robots.fetch(Tools.robots(), name) do
      {:ok, module} ->
        {:ok, module}

      {:error, :unknown_robot} ->
        {:error,
         Error.resource(:not_found, %{
           message: "unknown robot #{inspect(name)}; available: #{Tools.available_names()}"
         })}
    end
  end

  def fetch_robot(_),
    do:
      {:error,
       Error.resource(:not_found, %{
         message: "missing robot URI template variable"
       })}
end
