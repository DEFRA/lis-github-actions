#nullable enable
using System;
using System.Collections.Generic;
using System.Linq;


IReadOnlyList<string> GetCommandOutput(string fileName, string arguments)
{
    IEnumerable<string> output;
    IEnumerable<string> error;

    var exitCode = StartProcess(
        fileName,
        new ProcessSettings
        {
            Arguments = arguments,
            RedirectStandardOutput = true,
            RedirectStandardError = true
        },
        out output,
        out error);

    var outputLines = output.ToList();
    var errorLines = error.ToList();

    if (exitCode != 0)
    {
        foreach (var line in errorLines)
        {
            Error(line);
        }

        throw new Exception($"{fileName} {arguments} failed with exit code {exitCode}.");
    }

    return outputLines;
}

void RunCommand(string fileName, string arguments)
{
    GetCommandOutput(fileName, arguments);
}

string NpmExecutable => IsRunningOnWindows() ? "npm.cmd" : "npm";

void RunNpm(string arguments)
{
    Information($"> npm {arguments}");
    RunCommand(NpmExecutable, $"--cache \"./.cake/npm-cache\" {arguments}");
}

void RunNode(string arguments)
{
    Information($"> node {arguments}");
    RunCommand("node", arguments);
}

void RunNpx(string arguments)
{
    var executable = IsRunningOnWindows() ? "npx.cmd" : "npx";
    Information($"> npx {arguments}");
    RunCommand(executable, $"--cache \"./.cake/npm-cache\" {arguments}");
}

void RunGit(string arguments)
{
    RunCommand("git", arguments);
}

IReadOnlyList<string> GetGitOutput(string arguments) => GetCommandOutput("git", arguments);
