# SPDX-FileCopyrightText: 2026 James Harton
#
# SPDX-License-Identifier: Apache-2.0

defmodule BB.MCP.JsonSchema do
  @moduledoc """
  Converts BB command argument definitions into JSON Schema fragments.

  Used to advertise command argument types to MCP clients via the
  `list_commands` tool, so agents can know what to pass to `invoke_command`.

  Maps Spark `:type` values to JSON Schema types:

      :integer        -> %{"type" => "integer"}
      :float, :number -> %{"type" => "number"}
      :boolean        -> %{"type" => "boolean"}
      :string         -> %{"type" => "string"}
      :atom           -> %{"type" => "string", "description" => "atom"}
      :map, {:map, fields} -> %{"type" => "object"}
      :keyword_list   -> %{"type" => "object"}
      :any            -> %{}
      module          -> %{"description" => "complex type: \#{inspect(module)}"}
  """

  alias BB.Dsl.Command
  alias BB.Dsl.Command.Argument

  @doc """
  Build a JSON Schema object describing a command's arguments.
  """
  @spec for_command(Command.t()) :: map()
  def for_command(%Command{arguments: arguments}) do
    properties =
      arguments
      |> Enum.flat_map(&for_argument_properties/1)
      |> Map.new()

    required =
      arguments
      |> Enum.flat_map(&required_properties/1)

    base = %{"type" => "object", "properties" => properties}
    if required == [], do: base, else: Map.put(base, "required", required)
  end

  @doc """
  Build a JSON Schema fragment for a single command argument, including
  description and default value where present.
  """
  @spec for_argument(Argument.t()) :: map()
  def for_argument(%Argument{type: type, doc: doc, default: default}) do
    for_field(type, doc, default)
  end

  defp for_field(type, doc, default) do
    type
    |> base_schema()
    |> maybe_put("description", doc)
    |> maybe_put("default", default)
  end

  defp base_schema(:integer), do: %{"type" => "integer"}
  defp base_schema(:non_neg_integer), do: %{"type" => "integer", "minimum" => 0}
  defp base_schema(:pos_integer), do: %{"type" => "integer", "minimum" => 1}
  defp base_schema(:float), do: %{"type" => "number"}
  defp base_schema(:number), do: %{"type" => "number"}
  defp base_schema(:boolean), do: %{"type" => "boolean"}
  defp base_schema(:string), do: %{"type" => "string"}
  defp base_schema(:atom), do: %{"type" => "string"}
  defp base_schema(:map), do: %{"type" => "object"}
  defp base_schema({:map, _fields}), do: %{"type" => "object"}
  defp base_schema(:keyword_list), do: %{"type" => "object"}
  defp base_schema({:list, inner}), do: %{"type" => "array", "items" => base_schema(inner)}
  defp base_schema(:any), do: %{}

  defp base_schema(module) when is_atom(module),
    do: %{"description" => "complex type: #{inspect(module)}"}

  defp base_schema(_other), do: %{}

  defp for_argument_properties(%Argument{name: name, type: {:map, fields}, required: required}) do
    flatten_map_fields([Atom.to_string(name)], fields, required)
  end

  defp for_argument_properties(%Argument{name: name, type: :map} = arg) do
    json_name = "#{name}_json"
    json_doc = "JSON object for `#{name}`"
    [{json_name, for_argument(%{arg | type: :string, doc: json_doc})}]
  end

  defp for_argument_properties(%Argument{name: name} = arg) do
    [{Atom.to_string(name), for_argument(arg)}]
  end

  defp required_properties(%Argument{name: name, type: {:map, fields}, required: true}) do
    flatten_required_map_fields([Atom.to_string(name)], fields, true)
  end

  defp required_properties(%Argument{name: name, type: :map, required: true}),
    do: ["#{name}_json"]

  defp required_properties(%Argument{name: name, required: true}), do: [Atom.to_string(name)]
  defp required_properties(_arg), do: []

  defp flatten_map_fields(path, fields, parent_required) when is_list(fields) do
    Enum.flat_map(fields, fn {name, spec} ->
      flatten_map_field(path, name, spec, parent_required)
    end)
  end

  defp flatten_map_field(path, name, spec, parent_required) do
    type = field_type(spec)
    required = field_required?(spec, parent_required)

    case type do
      {:map, fields} ->
        flatten_map_fields(path ++ [Atom.to_string(name)], fields, required)

      type ->
        field_name = Enum.join(path ++ [Atom.to_string(name)], ".")
        [{field_name, field_schema(type, spec)}]
    end
  end

  defp field_schema(type, spec) when is_list(spec) do
    for_field(type, Keyword.get(spec, :doc), Keyword.get(spec, :default))
  end

  defp field_schema(type, _spec), do: for_field(type, nil, nil)

  defp field_type(spec) when is_list(spec), do: Keyword.fetch!(spec, :type)
  defp field_type(type), do: type

  defp field_required?(spec, parent_required) when is_list(spec),
    do: parent_required and Keyword.get(spec, :required, false)

  defp field_required?(_spec, parent_required), do: parent_required

  defp flatten_required_map_fields(path, fields, parent_required) when is_list(fields) do
    Enum.flat_map(fields, fn {name, spec} ->
      flatten_required_map_field(path, name, spec, parent_required)
    end)
  end

  defp flatten_required_map_field(path, name, spec, parent_required) do
    type = field_type(spec)
    required = field_required?(spec, parent_required)

    case type do
      {:map, fields} ->
        flatten_required_map_fields(path ++ [Atom.to_string(name)], fields, required)

      _type when required ->
        [Enum.join(path ++ [Atom.to_string(name)], ".")]

      _type ->
        []
    end
  end

  defp maybe_put(map, _key, nil), do: map
  defp maybe_put(map, key, value), do: Map.put(map, key, value)
end
