# SPDX-FileCopyrightText: 2026 James Harton
#
# SPDX-License-Identifier: Apache-2.0

defmodule BB.MCP.PeriSchema do
  @moduledoc """
  Converts BB command argument definitions into Peri schemas suitable for
  `Anubis.Server.Frame.register_tool/3`.

  Anubis takes the Peri schema we hand it, validates incoming tool calls
  against it, and re-renders it as JSON Schema on the wire. So one
  conversion suffices for both validation and discovery.

  BB types map to Peri types as follows:

      :integer | :pos_integer | :non_neg_integer -> :integer
      :float | :number                           -> :float
      :string                                    -> :string
      :boolean                                   -> :boolean
      :atom                                      -> :atom
      :map | {:map, fields}                     -> :map
      :keyword_list                              -> :keyword
      :any                                       -> :any
      module / unknown                           -> :any
  """

  alias BB.Dsl.Command
  alias BB.Dsl.Command.Argument

  @doc """
  Build a Peri schema (map keyed by argument name) for a command's arguments.
  """
  @spec for_command(Command.t()) :: map()
  def for_command(%Command{arguments: arguments}) do
    arguments
    |> Enum.flat_map(&for_argument_fields/1)
    |> Map.new()
  end

  @doc """
  Translate MCP-visible command params back to the command's original BB goal.
  """
  @spec to_goal(Command.t(), map()) :: map()
  def to_goal(%Command{arguments: arguments}, params) when is_map(params) do
    Map.new(arguments, fn %Argument{name: name} = arg -> {name, decode_argument(arg, params)} end)
    |> Map.reject(fn {_name, value} -> is_nil(value) end)
  end

  @doc """
  Pre-process incoming params before Peri validation.

  Some MCP clients interpret a flat property name like `"target.x"` as a nested
  path and send `%{"target" => %{"x" => ...}}` instead of `%{"target.x" => ...}`.
  We advertise the flat (dotted) form deliberately — nested object schemas are
  poorly supported by some clients — so we flatten any nested object back to
  the dotted form here before Peri's schema validator sees them.

  Also coerces JSON whole numbers (`0`, `1`) to floats for fields whose schema
  type is `:float` — JSON has no syntactic distinction between integer and
  float zero, but Peri's `:float` validator rejects integers.
  """
  @spec flatten_nested_params(Command.t(), map()) :: map()
  def flatten_nested_params(%Command{arguments: arguments} = command, params)
      when is_map(params) do
    arguments
    |> Enum.reduce(params, &flatten_arg_into_params/2)
    |> coerce_numeric_fields(command)
  end

  defp coerce_numeric_fields(params, %Command{} = command) do
    schema = for_command(command)

    Map.new(params, fn {key, value} ->
      {key, coerce_if_float(value, Map.get(schema, key))}
    end)
  end

  defp coerce_if_float(value, schema) when is_integer(value) do
    if float_type?(schema), do: value * 1.0, else: value
  end

  defp coerce_if_float(value, _schema), do: value

  defp float_type?(:float), do: true
  defp float_type?({:required, inner}), do: float_type?(inner)
  defp float_type?({inner, {:default, _}}) when not is_atom(inner), do: float_type?(inner)
  defp float_type?({:meta, inner, _}) when not is_atom(inner), do: float_type?(inner)
  defp float_type?(_), do: false

  defp flatten_arg_into_params(%Argument{name: name, type: {:map, _fields}}, params) do
    name_str = Atom.to_string(name)

    case Map.get(params, name_str) || Map.get(params, name) do
      nested when is_map(nested) ->
        params
        |> Map.drop([name, name_str])
        |> Map.merge(flatten_to_dotted(nested, name_str))

      _ ->
        params
    end
  end

  defp flatten_arg_into_params(_arg, params), do: params

  defp flatten_to_dotted(value, prefix) when is_map(value) do
    Enum.reduce(value, %{}, fn {key, val}, acc ->
      key_str = to_string(key)
      path = "#{prefix}.#{key_str}"

      if is_map(val) do
        Map.merge(acc, flatten_to_dotted(val, path))
      else
        Map.put(acc, path, val)
      end
    end)
  end

  @doc """
  Build a Peri field value for a single argument, applying `required` and
  `default` wrappers and a `description` meta tag where set.
  """
  @spec for_argument(Argument.t()) :: term()
  def for_argument(%Argument{type: type, doc: doc, required: required, default: default}) do
    for_field(type, required, doc, default)
  end

  defp for_field(type, required, doc, default) do
    type
    |> base_type()
    |> apply_default(default)
    |> apply_meta(doc)
    |> apply_required(required)
  end

  defp base_type(:integer), do: :integer
  defp base_type(:pos_integer), do: :integer
  defp base_type(:non_neg_integer), do: :integer
  defp base_type(:float), do: :float
  defp base_type(:number), do: :float
  defp base_type(:boolean), do: :boolean
  defp base_type(:string), do: :string
  defp base_type(:atom), do: :atom
  defp base_type(:map), do: :map
  defp base_type({:map, _fields}), do: :map
  defp base_type(:keyword_list), do: :keyword
  defp base_type(:any), do: :any
  defp base_type({:list, _inner}), do: {:list, :any}
  defp base_type(_other), do: :any

  defp decode_argument(%Argument{name: name, type: {:map, _fields}}, params) do
    cond do
      dotted_args = collect_dotted_args(params, name) -> dotted_args
      has_arg?(params, name) -> get_arg(params, name)
      true -> nil
    end
  end

  defp decode_argument(%Argument{name: name, type: :map}, params) do
    json_name = String.to_atom("#{name}_json")

    cond do
      dotted_args = collect_dotted_args(params, name) ->
        dotted_args

      has_arg?(params, json_name) ->
        decode_json_map(get_arg(params, json_name))

      has_arg?(params, name) ->
        get_arg(params, name)

      true ->
        nil
    end
  end

  defp decode_argument(%Argument{name: name}, params) do
    if has_arg?(params, name), do: get_arg(params, name)
  end

  defp decode_json_map(value) when is_binary(value) do
    case Jason.decode(value) do
      {:ok, decoded} when is_map(decoded) -> decoded
      _other -> value
    end
  end

  defp decode_json_map(value), do: value

  defp collect_dotted_args(params, name) do
    prefix = "#{name}."

    params
    |> Enum.reduce(%{}, fn
      {key, value}, acc when is_binary(key) ->
        if String.starts_with?(key, prefix) do
          key
          |> String.replace_prefix(prefix, "")
          |> String.split(".")
          |> put_nested(acc, value)
        else
          acc
        end

      _other, acc ->
        acc
    end)
    |> case do
      empty when empty == %{} -> nil
      dotted_args -> dotted_args
    end
  end

  defp for_argument_fields(%Argument{name: name, type: {:map, fields}, required: required}) do
    flatten_map_fields([Atom.to_string(name)], fields, required)
  end

  defp for_argument_fields(%Argument{name: name, type: :map} = arg) do
    json_name = String.to_atom("#{name}_json")
    json_doc = "JSON object for `#{name}`"
    [{json_name, for_argument(%{arg | type: :string, doc: json_doc})}]
  end

  defp for_argument_fields(%Argument{name: name} = arg), do: [{name, for_argument(arg)}]

  defp get_arg(params, name) when is_atom(name),
    do: Map.get(params, name, Map.get(params, Atom.to_string(name)))

  defp get_arg(params, name) when is_binary(name), do: Map.get(params, name)

  defp has_arg?(params, name) when is_atom(name),
    do: Map.has_key?(params, name) or Map.has_key?(params, Atom.to_string(name))

  defp has_arg?(params, name) when is_binary(name), do: Map.has_key?(params, name)

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
        [{field_name, field_schema(type, spec, required)}]
    end
  end

  defp field_schema(type, spec, required) when is_list(spec) do
    for_field(type, required, Keyword.get(spec, :doc), Keyword.get(spec, :default))
  end

  defp field_schema(type, _spec, required), do: for_field(type, required, nil, nil)

  defp field_type(spec) when is_list(spec), do: Keyword.fetch!(spec, :type)
  defp field_type(type), do: type

  defp field_required?(spec, parent_required) when is_list(spec),
    do: parent_required and Keyword.get(spec, :required, false)

  defp field_required?(_spec, parent_required), do: parent_required

  defp put_nested([], acc, _value), do: acc
  defp put_nested([key], acc, value), do: Map.put(acc, key, value)

  defp put_nested([key | rest], acc, value) do
    nested = Map.get(acc, key, %{})
    Map.put(acc, key, put_nested(rest, nested, value))
  end

  defp apply_default(type, nil), do: type
  defp apply_default(type, value), do: {type, {:default, value}}

  defp apply_meta(type, nil), do: type
  defp apply_meta(type, doc), do: {:meta, type, description: doc}

  defp apply_required(type, true), do: {:required, type}
  defp apply_required(type, _), do: type
end
