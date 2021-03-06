defmodule ExLoader do
  @moduledoc """
  Documentation for ExLoader.
  """

  @beam_ext ".beam"

  @doc """
  Check if given file is valid or not
  """
  @spec valid_file?(String.t()) :: boolean
  def valid_file?(src), do: ExLoader.File.valid_file?(src)

  @doc """
  load a single beam to a remote node

  Behind the scenes, it uses `:code.load_abs/1`.
  ## Examples
      iex> ExLoader.load_module("hello.beam")
      {:ok, Hello}
      iex> :rpc.call(node(), Hello, :say, ["world"])
      "hello world"
  """
  @spec load_module(String.t()) :: {:ok, atom} | {:error, term}
  @spec load_module(String.t(), node) :: {:ok, atom} | {:error, term}
  def load_module(beam_file), do: load_module(beam_file, node())

  def load_module(beam_file, remote_node) do
    with {:ok, dst} <- ExLoader.File.copy(remote_node, beam_file),
         {:ok, module} <- load(remote_node, dst) do
      {:ok, module}
    else
      err -> err
    end
  end

  @doc """
  load a list of apps from a release (generated by distillery) to remote node.

  Behind the scenes, it copies the tarball to remote node, extracts it, add all beam folders by using ``:code.add_path``, load the configration from sys.config and then start the given apps.

  ## Examples
      iex> ExLoader.load_apps("example_app.tar.gz")
      :ok
      iex> :rpc.call(node(), ExampleApp.Server, :hello, ["world"])
      "hello world"
  """

  @spec load_apps(String.t(), [atom]) :: {:ok, atom} | {:error, term}
  @spec load_apps(String.t(), [atom], node) :: {:ok, atom} | {:error, term}
  def load_apps(tarball, apps), do: load_apps(tarball, apps, node())

  def load_apps(tarball, apps, remote_node) do
    with {:ok, dst} <- ExLoader.File.copy(remote_node, tarball),
         :ok <- ExLoader.File.uncompress(remote_node, dst) do
      ExLoader.Release.load(remote_node, Path.dirname(dst), apps)
    else
      err -> err
    end
  end

  @doc """
  load a release (generated by distillery) to remote node.

  Behind the scenes, it copies the tarball to remote node, extracts it, add all beam folders by using ``:code.add_path``, load the configration from sys.config and then start all the apps.

  ## Examples
      iex> ExLoader.load_release("example_complex_app.tar.gz")
      :ok
      iex> # assume example_complex_app.tar.gz contains a http server. Now http://hostname:8888/hello is available.
      nil
      iex> HttpPoison.get("http://hostname:8888/hello/?msg=world")
      {:ok, %HTTPoison.Response{body: "hello world", ...}}
  """

  @spec load_release(String.t()) :: {:ok, atom} | {:error, term}
  @spec load_release(String.t(), node) :: {:ok, atom} | {:error, term}
  def load_release(tarball), do: load_release(tarball, node())

  def load_release(tarball, remote_node) do
    load_apps(tarball, nil, remote_node)
  end

  defp load(remote_node, dst) do
    # :code.load_abs requires a file without extentions. weird.
    file = String.trim_trailing(dst, @beam_ext)
    result = :rpc.call(remote_node, :code, :load_abs, [to_charlist(file)])

    case result do
      {:module, module} ->
        {:ok, module}

      {:error, reason} ->
        {:error,
         %{
           msg:
             "Cannot load the file from remote node #{inspect(remote_node)}. Reason: #{
               inspect(reason)
             }",
           reason: reason
         }}
    end
  end
end
