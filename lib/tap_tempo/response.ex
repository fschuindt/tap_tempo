defmodule TapTempo.Response do
  @moduledoc false

  defstruct [
    :type,
    :message
  ]

  @type t :: %__MODULE__{
          type: atom(),
          message: String.t()
        }
end
