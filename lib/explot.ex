defmodule Explot do
  @moduledoc """
  The main module of this package. It provides an easy way to use Python's Matplotlib.
  It allows to send arbitrary commands to be interpreted by Python.
  It also provides functions to make it easy to use the most common functionality of Matplotlib.
  There will be more functions and accepting more params in the future but this module will not wrap
  all the functionality of matplotlib (which is huge).
  """

  @doc """
    Returns a plotter which can receive plotting commands
  """
  def new do
    python_script = """
import sys
import matplotlib.pyplot as plt
for line in sys.stdin:
  eval(line)
"""
    cmd = "python3 -c \"#{python_script}\""
    port_to_python = Port.open({:spawn, cmd}, [:binary])
    {:ok, agent} = Agent.start fn -> Map.new([port: port_to_python]) end
    agent
  end

  @doc """
    Sets the label on the X axis of the plot. This must be setup before showing the plot.
  """
  def xlabel(agent, label) do
    plot_command(agent, "xlabel('#{label}')")
  end

  @doc """
    Sets the label on the Y axis of the plot. This must be setup before showing the plot.
  """
  def ylabel(agent, label) do
    plot_command(agent, "ylabel('#{label}')")
  end

  @doc """
    Sets the title of the plot. This must be setup before showing the plot.
  """
  def title(agent, label) do
    plot_command(agent, "title('#{label}')")
  end

  @doc """
    Adds a list of data with a name to the plot.
  """
  def add_list(agent, list, list_name) do
    plot_command(agent, "plot(#{to_python_array(list)}, label='#{list_name}')")
  end

  @doc """
    Adds a list of labels to the X axis of the plot.
    The difference with the xlabel function is that xlabel names the whole axis while this function
    names different points along the axis.
    For instance xlabel may be "Date" while x_axis_labels are 2016-03-12, 2016-06-15, 2016-09-15, etc.
  """
  def x_axis_labels(agent, array_of_labels) do
    {labels_available, array_of_indexes} = limit_indexes(array_of_labels)
    labels_to_print = to_python_array(labels_available)
    plot_command(agent, "xticks(#{to_python_array(array_of_indexes)}, #{labels_to_print})") #, rotation=60)")
  end
  
  @doc """
    Draws a line plot. `xs` is an array of x coordinates, for example `[1.0, 1.5, 2.0]`.
    `ys` is an array of y coordinates.
  """
  def plot(agent, xs, ys, opts \\ []) do
    xs_str = numbers_to_python_array(xs)
    ys_str = numbers_to_python_array(ys)
    opts_str = opts_to_string(opts)
    plot_command(agent, "plot(#{xs_str}, #{ys_str}#{opts_str})")
  end

  @doc """
    Draws a scatter plot. `xs` is an array of x coordinates, for example `[1.0, 1.5, 2.0]`.
    `ys` is an array of y coordinates.
  """
  def scatter(agent, xs, ys, opts \\ []) do
    xs_str = numbers_to_python_array(xs)
    ys_str = numbers_to_python_array(ys)
    opts_str = opts_to_string(opts)
    plot_command(agent, "scatter(#{xs_str}, #{ys_str}#{opts_str})")
  end
  
  @doc """
    Encodes optional arguments.
  """
  def opts_to_string([]), do: ""
  def opts_to_string(opts) do
    "," <> (opts
    |> Enum.map(fn {key, value} -> opt_to_string(key, value) end)
    |> Enum.join(", "))
  end
  
  @doc """
    Encodes a single optional argument.
  """
  def opt_to_string(key, value) do
    "#{key}=#{to_python value}"
  end

  @doc """
    Shows the legend.
  """
  def legend(agent) do
    plot_command(agent, "legend()")
  end

  @doc """
    Changes the axis.
  """
  def axis(agent, desc) do
    plot_command(agent, "axis(#{to_python desc})")
  end

  @doc """
    Toggles the grid.
  """
  def grid(agent, is_show) do
    plot_command(agent, "grid(#{to_python is_show})")
  end

  @doc """
    Shows the plot and kills the agent.
  """
  def show(agent, opts \\ [pure: false]) do
    if opts[:pure] == false do
      grid(agent, true)
      legend(agent)
    end
    
    plot_command(agent, "show()")
    Port.close(port(agent))
    Agent.stop(agent, :normal)
  end

  @doc """
    Shows the plot without specifically turning on grids and legends, then kills the agent.
  """
  def show_pure(agent) do
    show(agent, pure: true)
  end

  @doc """
    Allows sending commands to the plotter. Provides flexibility for advanced users
  """
  def plot_command(agent, command) do
    send_command(agent, "plt.#{command}")
  end

  @doc """
    Allows sending arbitrary commands to the python process. Use with care.
  """
  def send_command(agent, command) do
    true = Port.command(port(agent), "#{command}\n")
  end

  defp port(agent) do
    Agent.get(agent, &Map.get(&1, :port))
  end
  
  @doc """
    Encodes an array of numbers.
  """
  def numbers_to_python_array(objs) do
    inspect objs, charlists: :as_lists, limit: :infinity
  end

  @doc """
    Encodes various data types to Python.
  """
  def to_python(true), do: "True"
  def to_python(false), do: "False"
  
  def to_python(str) when is_binary(str) do
    str = String.replace(str, "\\", "\\\\")
    str = String.replace(str, "\"", "\\\"")
    str = String.replace(str, "\r", "\\r")
    str = String.replace(str, "\n", "\\n")
    str = String.replace(str, "\t", "\\t")
    "\"#{str}\""
  end
  
  def to_python(any), do: "#{any}"

  defp to_python_array([h | t]) when is_number(h) do
    comma_separated = [h | t] |> Enum.join(", ")
    "[#{comma_separated}]"
  end

  defp to_python_array([h | t]) when is_binary(h) do
    comma_separated = [h | t] |> Enum.map(fn(x) -> "'#{x}'" end) |> Enum.join(", ")
    "[#{comma_separated}]"
  end

  defp to_python_array([h | t]) when is_map(h) do
    comma_separated = [h | t] |> Enum.map(fn(x) -> "'#{Date.to_iso8601(x)}'" end) |> Enum.join(", ")
    "[#{comma_separated}]"
  end

  # Limits the amount of indexes shown in the graph so data is readable
  defp limit_indexes(array) do
    divisor = Enum.max([round(Float.floor(length(array) /10)), 1])
    data = Enum.take_every(array, divisor)
    indexes = Enum.take_every(Enum.to_list((0..length(array)) - 1), divisor)
    {data, indexes}
  end

end
