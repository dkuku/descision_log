defmodule DecisionLog.ReadmeTest do
  use ReadmeTester.Case,
    files: ["README.md"],
    base_path: File.cwd!(),
    skip_patterns: [
      ~r/def deps do/,
      ~r/config :/,
      ~r/@decorate/
    ]
end
