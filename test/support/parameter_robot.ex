# SPDX-FileCopyrightText: 2026 James Harton
#
# SPDX-License-Identifier: Apache-2.0

defmodule BB.MCP.ParameterRobot do
  @moduledoc """
  A robot which declares runtime parameters, for exercising the parameter
  tools and resource against a real schema.

  A `{:unit, _}` parameter's value is a `Localize.Unit` struct, which is not
  JSON on its own.
  """
  use BB
  import BB.Unit

  topology do
    link :base do
      joint :shoulder do
        type(:revolute)

        limit do
          lower(~u(-90 degree))
          upper(~u(90 degree))
          effort(~u(1 newton_meter))
          velocity(~u(90 degree_per_second))
        end

        link(:arm)
      end
    end
  end

  parameters do
    group :motion do
      param(:max_speed,
        type: :float,
        default: 1.0,
        min: 0.0,
        max: 10.0,
        doc: "Maximum end effector speed"
      )

      param(:trim,
        type: {:unit, :degree},
        default: ~u(0 degree),
        min: ~u(-30 degree),
        max: ~u(30 degree),
        doc: "Shoulder zero offset"
      )

      param(:slew_rate, type: {:unit, :degree_per_second}, default: ~u(45 degree_per_second))
    end
  end
end
