{ lib, pkgs }:

{
  registry = import ./registry.nix;
  getBuildSystem = entry: entry.buildSystem or "autotools";
  getSource = entry: entry.source or "github";
  fetchSource =
    entry:
    let
      source = entry.source or "github";
      sha256 = entry.sha256 or lib.fakeHash;
    in
    if source == "system" then
      null
    else if source == "gitlab" then
      (
        if lib.hasAttr "tag" entry then
          pkgs.fetchgit {
            url = "https://gitlab.freedesktop.org/${entry.owner}/${entry.repo}.git";
            rev = "refs/tags/${entry.tag}";
            sha256 = sha256;
          }
        else if lib.hasAttr "branch" entry then
          pkgs.fetchgit {
            url = "https://gitlab.freedesktop.org/${entry.owner}/${entry.repo}.git";
            rev = "refs/heads/${entry.branch}";
            sha256 = sha256;
          }
        else if lib.hasAttr "rev" entry then
          pkgs.fetchFromGitLab {
            domain = "gitlab.freedesktop.org";
            owner = entry.owner;
            repo = entry.repo;
            rev = entry.rev;
            sha256 = sha256;
          }
        else
          throw "GitLab source requires 'rev', 'tag', or 'branch'"
      )
    else
      (
        if lib.hasAttr "tag" entry then
          pkgs.fetchFromGitHub {
            owner = entry.owner;
            repo = entry.repo;
            rev = entry.tag;
            sha256 = sha256;
          }
        else if lib.hasAttr "rev" entry then
          # Handle "master", "main", or "HEAD" as branch names
          if entry.rev == "master" || entry.rev == "main" || entry.rev == "HEAD" then
            pkgs.fetchgit {
              url = "https://github.com/${entry.owner}/${entry.repo}.git";
              rev = "refs/heads/${if entry.rev == "HEAD" then "main" else entry.rev}";
              sha256 = sha256;
            }
          else
            pkgs.fetchFromGitHub {
              owner = entry.owner;
              repo = entry.repo;
              rev = entry.rev;
              sha256 = sha256;
            }
        else
          throw "GitHub source requires either 'rev' or 'tag'"
      );
}

