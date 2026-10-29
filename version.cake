#nullable enable
#load "base.cake"
using System;
using System.Linq;
using System.Text.RegularExpressions;

var hotfixBranchPattern = new Regex(@"^hotfix/(lreg-[0-9]+)-.+$");
var featureBranchPattern = new Regex(@"^feature/(lreg-[0-9]+)-.+$");
var stableTagPattern = new Regex(@"^[0-9]+\.[0-9]+\.[0-9]+$");
var versionPattern = new Regex(
    @"^[0-9]+\.[0-9]+\.[0-9]+(?:-lreg-[0-9]+\.alpha\.[1-9][0-9]*)?$");

string ResolveRepositoryBranchName(string? branchName = null)
{
    var resolvedBranchName = branchName;

    if (string.IsNullOrWhiteSpace(resolvedBranchName))
    {
        resolvedBranchName = EnvironmentVariable("GITHUB_HEAD_REF");
    }

    if (string.IsNullOrWhiteSpace(resolvedBranchName))
    {
        resolvedBranchName = EnvironmentVariable("GITHUB_REF_NAME");
    }

    if (string.IsNullOrWhiteSpace(resolvedBranchName))
    {
        resolvedBranchName = GetGitOutput("branch --show-current").FirstOrDefault();
    }

    if (string.IsNullOrWhiteSpace(resolvedBranchName))
    {
        throw new Exception("Unable to determine the branch name.");
    }

    return resolvedBranchName.ToLowerInvariant();
}

void FetchRepositoryVersionState()
{
    RunGit("fetch --force --tags origin +refs/heads/main:refs/remotes/origin/main");
}

string CalculateVersion(string? branchName = null, bool stable = false)
{
    FetchRepositoryVersionState();

    var resolvedBranchName = ResolveRepositoryBranchName(branchName);
    var hotfixMatch = hotfixBranchPattern.Match(resolvedBranchName);
    string storyId;
    string bumpType;

    if (hotfixMatch.Success)
    {
        storyId = hotfixMatch.Groups[1].Value;
        bumpType = "patch";
    }
    else
    {
        var featureMatch = featureBranchPattern.Match(resolvedBranchName);

        if (!featureMatch.Success)
        {
            throw new Exception($"Branch '{resolvedBranchName}' does not have the correct name.");
        }

        storyId = featureMatch.Groups[1].Value;
        bumpType = "minor";
    }

    var latestMainTag = GetGitOutput("tag --merged origin/main --sort=-v:refname")
        .FirstOrDefault(line => stableTagPattern.IsMatch(line));

    var major = 0;
    var minor = 0;
    var patch = 0;

    if (!string.IsNullOrWhiteSpace(latestMainTag))
    {
        var parts = latestMainTag.Split('.');
        major = int.Parse(parts[0]);
        minor = int.Parse(parts[1]);
        patch = int.Parse(parts[2]);
    }

    if (bumpType.Equals("minor", StringComparison.OrdinalIgnoreCase))
    {
        minor += 1;
        patch = 0;
    }
    else
    {
        patch += 1;
    }

    var baseVersion = $"{major}.{minor}.{patch}";
    string version;

    if (!stable)
    {
        var mergeBase = GetGitOutput("merge-base HEAD origin/main").First();
        var depthValue = GetGitOutput($"rev-list --count {mergeBase}..HEAD").First();
        int depth;

        if (!int.TryParse(depthValue, out depth) || depth < 1)
        {
            depth = 1;
        }

        version = $"{baseVersion}-{storyId}.alpha.{depth}";
    }
    else
    {
        version = baseVersion;
    }

    if (!versionPattern.IsMatch(version))
    {
        throw new Exception($"Calculated version '{version}' is not valid.");
    }

    Information($"Resolved branch '{resolvedBranchName}' with story '{storyId}' and bump '{bumpType}'.");

    return version;
}

Task("GetVersion")
    .Description("Calculates the version and sets it as a GitHub Actions output")
    .Does(() => {
        var branchName = Argument("branch", "");
        var releaseType = Argument("release_type", "prerelease");

        if (releaseType != "prerelease" && releaseType != "stable")
        {
            throw new Exception(
                $"Release type '{releaseType}' is invalid. Use 'prerelease' or 'stable'.");
        }

        var version = CalculateVersion(branchName, releaseType == "stable");
        Information($"Calculated Version: {version}");

        if (BuildSystem.GitHubActions.IsRunningOnGitHubActions)
        {
            var outputFile = EnvironmentVariable("GITHUB_OUTPUT");
            if (!string.IsNullOrEmpty(outputFile))
            {
                System.IO.File.AppendAllLines(outputFile, new[] { $"version={version}" });
            }
            else
            {
                Warning("GITHUB_OUTPUT environment variable not found.");
            }
        }
    });

var targetVersion = Argument("target", "");
if (targetVersion == "GetVersion")
{
    RunTarget("GetVersion");
}
