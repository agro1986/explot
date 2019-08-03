defmodule Explot.Style do
  @moduledoc false
  
  import Explot

  def use(agent, style_name) do
    plot_command(agent, "style.use(#{to_python style_name})")
  end
end
