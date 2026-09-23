defmodule PosbdWeb.Api.ChangesetJSON do
  @doc """
  Renders changeset errors as `%{errors: %{field: ["message"]}}`, the
  shape every bulk-import/validation screen in the frontend expects.
  """
  def error(%{changeset: changeset}) do
    %{errors: Ecto.Changeset.traverse_errors(changeset, &translate_error/1)}
  end

  defp translate_error({msg, opts}) do
    Enum.reduce(opts, msg, fn {key, value}, acc ->
      placeholder = "%{#{key}}"

      if String.contains?(acc, placeholder) do
        String.replace(acc, placeholder, stringify(value))
      else
        acc
      end
    end)
  end

  defp stringify(value) when is_list(value), do: Enum.join(value, ", ")
  defp stringify(value), do: to_string(value)
end
