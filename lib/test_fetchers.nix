{ fetchers, ... }:

{
  unquoteURL = {
    testCommonEscapes = {
      expr = fetchers.unquoteURL "hello%2Fworld%3Fuser%40example.com";
      expected = "hello/world?user@example.com";
    };

    testLowercaseEscapes = {
      expr = fetchers.unquoteURL "release%2f2024%3fok%3dyes%20please";
      expected = "release/2024?ok=yes please";
    };
  };

  defaultGitForgeHosts = {
    testDefaults = {
      expr = fetchers.defaultGitForgeHosts;
      expected = {
        "github.com" = "github";
        "gitlab.com" = "gitlab";
        "git.sr.ht" = "sourcehut";
      };
    };
  };

  parseForgeProject = {
    testGitHubProject = {
      expr = fetchers.parseForgeProject "github" [
        "pypa"
        "pip"
      ];
      expected = {
        owner = "pypa";
        repo = "pip";
      };
    };

    testGitLabNestedGroupProject = {
      expr = fetchers.parseForgeProject "gitlab" [
        "company"
        "platform"
        "internal-package"
      ];
      expected = {
        owner = "company%2Fplatform";
        repo = "internal-package";
      };
    };

    testInvalidGitHubProject = {
      expr = fetchers.parseForgeProject "github" [ "owner" ];
      expected = null;
    };
  };

  parseGitSource = {
    testParsesGitPlusQueryAndFragment = {
      expr = fetchers.parseGitSource "git+https://github.com/pypa/pip.git?tag=20.3.1#f94a429e17b450ac2d3432f46492416ac2cf58ad";
      expected = {
        url = "https://github.com/pypa/pip.git";
        query = {
          tag = "20.3.1";
        };
        fragment = "f94a429e17b450ac2d3432f46492416ac2cf58ad";
        lockedRev = "f94a429e17b450ac2d3432f46492416ac2cf58ad";
        fetchGitRef = "refs/tags/20.3.1";
        fetchTreeRef = "20.3.1";
      };
    };

    testUsesQueryRevWhenItIsHash = {
      expr = fetchers.parseGitSource "https://example.com/repo.git?rev=0123456789abcdef0123456789abcdef01234567";
      expected = {
        url = "https://example.com/repo.git";
        query = {
          rev = "0123456789abcdef0123456789abcdef01234567";
        };
        fragment = "";
        lockedRev = "0123456789abcdef0123456789abcdef01234567";
        fetchGitRef = null;
        fetchTreeRef = "0123456789abcdef0123456789abcdef01234567";
      };
    };

    testDecodesLowercaseQueryEscapes = {
      expr = fetchers.parseGitSource "https://example.com/repo.git?branch=release%2f2024&subdirectory=src%2fpython";
      expected = {
        url = "https://example.com/repo.git";
        query = {
          branch = "release/2024";
          subdirectory = "src/python";
        };
        fragment = "";
        lockedRev = null;
        fetchGitRef = "refs/heads/release/2024";
        fetchTreeRef = "release/2024";
      };
    };
  };

  parseGitRemote = {
    testParsesScpLikeRemote = {
      expr = fetchers.parseGitRemote "git@gitlab.example.com:company/platform/internal-package.git";
      expected = {
        authority = "gitlab.example.com";
        host = "gitlab.example.com";
        hostLower = "gitlab.example.com";
        hasPort = false;
        path = "company/platform/internal-package";
        segments = [
          "company"
          "platform"
          "internal-package"
        ];
      };
    };

    testParsesPortedHttpsRemote = {
      expr = fetchers.parseGitRemote "https://gitlab.example.com:8443/company/internal-package.git";
      expected = {
        authority = "gitlab.example.com:8443";
        host = "gitlab.example.com";
        hostLower = "gitlab.example.com";
        hasPort = true;
        path = "company/internal-package";
        segments = [
          "company"
          "internal-package"
        ];
      };
    };

    testParsesGitProtocolRemote = {
      expr = fetchers.parseGitRemote "GIT://GitHub.com/pypa/pip.git";
      expected = {
        authority = "github.com";
        host = "GitHub.com";
        hostLower = "github.com";
        hasPort = false;
        path = "pypa/pip";
        segments = [
          "pypa"
          "pip"
        ];
      };
    };
  };

  selectGitFetcher = {
    testDefaultsToFetchGit = {
      expr =
        fetchers.selectGitFetcher
          {
            config = { };
            hasFetchTree = true;
          }
          (
            fetchers.parseGitSource "https://github.com/pypa/pip.git#f94a429e17b450ac2d3432f46492416ac2cf58ad"
          );
      expected = {
        fetcher = "fetchGit";
        args = {
          url = "https://github.com/pypa/pip.git";
          rev = "f94a429e17b450ac2d3432f46492416ac2cf58ad";
          allRefs = true;
          submodules = true;
        };
      };
    };

    testGitHubUsesFetchTreeInAutoMode = {
      expr =
        fetchers.selectGitFetcher
          {
            config.git-fetcher = "auto";
            hasFetchTree = true;
          }
          (
            fetchers.parseGitSource "https://github.com/pypa/pip.git#f94a429e17b450ac2d3432f46492416ac2cf58ad"
          );
      expected = {
        fetcher = "fetchTree";
        args = {
          type = "github";
          owner = "pypa";
          repo = "pip";
          rev = "f94a429e17b450ac2d3432f46492416ac2cf58ad";
        };
      };
    };

    testCustomGitLabHostUsesFetchTreeInAutoMode = {
      expr =
        fetchers.selectGitFetcher
          {
            config.git-fetcher = "auto";
            config.git-forge-hosts."gitlab.example.com" = "gitlab";
            hasFetchTree = true;
          }
          (
            fetchers.parseGitSource "https://gitlab.example.com/company/platform/internal-package.git#0123456789abcdef0123456789abcdef01234567"
          );
      expected = {
        fetcher = "fetchTree";
        args = {
          type = "gitlab";
          owner = "company%2Fplatform";
          repo = "internal-package";
          host = "gitlab.example.com";
          rev = "0123456789abcdef0123456789abcdef01234567";
        };
      };
    };

    testCustomHostConfigPreservesBuiltInHosts = {
      expr =
        fetchers.selectGitFetcher
          {
            config = {
              git-fetcher = "auto";
              git-forge-hosts."gitlab.example.com" = "gitlab";
            };
            hasFetchTree = true;
          }
          (
            fetchers.parseGitSource "https://github.com/pypa/pip.git#f94a429e17b450ac2d3432f46492416ac2cf58ad"
          );
      expected = {
        fetcher = "fetchTree";
        args = {
          type = "github";
          owner = "pypa";
          repo = "pip";
          rev = "f94a429e17b450ac2d3432f46492416ac2cf58ad";
        };
      };
    };

    testUnknownHostFallsBackToFetchGit = {
      expr =
        fetchers.selectGitFetcher
          {
            config = { };
            hasFetchTree = true;
          }
          (
            fetchers.parseGitSource "https://git.example.com/company/internal-package.git#0123456789abcdef0123456789abcdef01234567"
          );
      expected = {
        fetcher = "fetchGit";
        args = {
          url = "https://git.example.com/company/internal-package.git";
          rev = "0123456789abcdef0123456789abcdef01234567";
          allRefs = true;
          submodules = true;
        };
      };
    };

    testBranchWithoutLockedRevUsesFetchTreeRef = {
      expr = fetchers.selectGitFetcher {
        config.git-fetcher = "auto";
        hasFetchTree = true;
      } (fetchers.parseGitSource "https://github.com/pypa/pip.git?branch=main");
      expected = {
        fetcher = "fetchTree";
        args = {
          type = "github";
          owner = "pypa";
          repo = "pip";
          ref = "main";
        };
      };
    };

    testMalformedRemoteFallsBackToFetchGit = {
      expr = fetchers.selectGitFetcher {
        config = { };
        hasFetchTree = true;
      } (fetchers.parseGitSource "not-a-url");
      expected = {
        fetcher = "fetchGit";
        args = {
          url = "not-a-url";
          allRefs = true;
          submodules = true;
        };
      };
    };

    testForceGitOverridesAuto = {
      expr =
        fetchers.selectGitFetcher
          {
            config = {
              git-fetcher = "auto";
              git-fetcher-force-git = [ "github.com/pypa/pip" ];
            };
            hasFetchTree = true;
          }
          (
            fetchers.parseGitSource "https://github.com/pypa/pip.git#f94a429e17b450ac2d3432f46492416ac2cf58ad"
          );
      expected = {
        fetcher = "fetchGit";
        args = {
          url = "https://github.com/pypa/pip.git";
          rev = "f94a429e17b450ac2d3432f46492416ac2cf58ad";
          allRefs = true;
          submodules = true;
        };
      };
    };

    testAutoFallsBackWhenFetchTreeUnavailable = {
      expr =
        fetchers.selectGitFetcher
          {
            config.git-fetcher = "auto";
            hasFetchTree = false;
          }
          (
            fetchers.parseGitSource "https://github.com/pypa/pip.git#f94a429e17b450ac2d3432f46492416ac2cf58ad"
          );
      expected = {
        fetcher = "fetchGit";
        args = {
          url = "https://github.com/pypa/pip.git";
          rev = "f94a429e17b450ac2d3432f46492416ac2cf58ad";
          allRefs = true;
          submodules = true;
        };
      };
    };
  };
}
