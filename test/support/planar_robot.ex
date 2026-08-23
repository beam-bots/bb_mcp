# SPDX-FileCopyrightText: 2026 James Harton
#
# SPDX-License-Identifier: Apache-2.0

defmodule BB.MCP.PlanarRobot do
  @moduledoc """
  A robot whose chain starts at a planar joint, for exercising resources
  against joints with more than one degree of freedom.

  A planar joint's configuration is a `BB.Math.Transform2D` and its velocity a
  `BB.Message.Geometry.Twist2D`, neither of which is JSON on its own.
  """
  use BB
  import BB.Unit

  topology do
    link :world do
      joint :ground do
        type(:planar)

        axis do
        end

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
    end
  end
end
