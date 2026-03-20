defmodule SymphonyElixir.ShellUtilsTest do
  use ExUnit.Case, async: true

  alias SymphonyElixir.ShellUtils

  describe "windows?/0" do
    test "returns a boolean" do
      assert is_boolean(ShellUtils.windows?())
    end
  end

  describe "shell_command/2" do
    test "bash shell uses -lc flag" do
      assert {"/usr/bin/bash", ["-lc", "echo hi"]} =
               ShellUtils.shell_command("/usr/bin/bash", "echo hi")
    end

    test "sh shell uses -c flag" do
      assert {"/bin/sh", ["-c", "echo hi"]} =
               ShellUtils.shell_command("/bin/sh", "echo hi")
    end

    test "cmd shell uses /C flag" do
      assert {"cmd.exe", ["/C", "echo hi"]} =
               ShellUtils.shell_command("cmd.exe", "echo hi")
    end

    test "powershell uses -NoProfile -Command" do
      assert {"powershell.exe", ["-NoProfile", "-Command", "echo hi"]} =
               ShellUtils.shell_command("powershell.exe", "echo hi")
    end

    test "unknown shell falls back to a valid flag" do
      {"unknown_shell", [flag, "echo hi"]} =
        ShellUtils.shell_command("unknown_shell", "echo hi")

      assert flag in ["-c", "/C"]
    end
  end

  describe "shell_args/1" do
    test "bash returns [-lc]" do
      assert ["-lc"] = ShellUtils.shell_args("/usr/bin/bash")
    end

    test "sh returns [-c]" do
      assert ["-c"] = ShellUtils.shell_args("/bin/sh")
    end

    test "cmd returns [/C]" do
      assert ["/C"] = ShellUtils.shell_args("cmd.exe")
    end

    test "powershell returns expected args" do
      assert ["-NoProfile", "-Command"] = ShellUtils.shell_args("powershell.exe")
    end
  end

  describe "find_bash_path/0" do
    test "returns a string or nil" do
      result = ShellUtils.find_bash_path()
      assert is_nil(result) or is_binary(result)
    end
  end

  describe "default_shell/0" do
    test "returns a non-empty string" do
      result = ShellUtils.default_shell()
      assert is_binary(result)
      assert result != ""
    end
  end

  describe "default_hook_shell/0" do
    test "returns a non-empty string" do
      result = ShellUtils.default_hook_shell()
      assert is_binary(result)
      assert result != ""
    end
  end
end
