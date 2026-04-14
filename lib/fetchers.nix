{ lib, ... }:

let
  inherit (lib)
    length
    elem
    head
    tail
    elemAt
    concatStringsSep
    match
    listToAttrs
    splitString
    filter
    nameValuePair
    optionalAttrs
    versionAtLeast
    toLower
    removeSuffix
    ;
  inherit (builtins)
    nixVersion
    map
    replaceStrings
    stringLength
    substring
    ;

  splitOnce = separator: value: {
    before = head (splitString separator value);
    after =
      let
        parts = splitString separator value;
      in
      if length parts > 1 then concatStringsSep separator (tail parts) else null;
  };

  stripGitTransportPrefix =
    url:
    if stringLength url >= 4 && toLower (substring 0 4 url) == "git+" then
      substring 4 ((stringLength url) - 4) url
    else
      url;

  urlEscapePairs = [
    {
      encoded = "%20";
      decoded = " ";
    }
    {
      encoded = "%21";
      decoded = "!";
    }
    {
      encoded = "%23";
      decoded = "#";
    }
    {
      encoded = "%24";
      decoded = "$";
    }
    {
      encoded = "%26";
      decoded = "&";
    }
    {
      encoded = "%27";
      decoded = "'";
    }
    {
      encoded = "%28";
      decoded = "(";
    }
    {
      encoded = "%29";
      decoded = ")";
    }
    {
      encoded = "%2A";
      decoded = "*";
    }
    {
      encoded = "%2B";
      decoded = "+";
    }
    {
      encoded = "%2C";
      decoded = ",";
    }
    {
      encoded = "%2F";
      decoded = "/";
    }
    {
      encoded = "%3A";
      decoded = ":";
    }
    {
      encoded = "%3B";
      decoded = ";";
    }
    {
      encoded = "%3D";
      decoded = "=";
    }
    {
      encoded = "%3F";
      decoded = "?";
    }
    {
      encoded = "%40";
      decoded = "@";
    }
    {
      encoded = "%5B";
      decoded = "[";
    }
    {
      encoded = "%5D";
      decoded = "]";
    }
  ];

  unquoteURL = replaceStrings (
    (map (pair: pair.encoded) urlEscapePairs) ++ (map (pair: toLower pair.encoded) urlEscapePairs)
  ) ((map (pair: pair.decoded) urlEscapePairs) ++ (map (pair: pair.decoded) urlEscapePairs));

  parseURLQuery =
    query:
    if query == null || query == "" then
      { }
    else
      listToAttrs (
        map (
          param:
          let
            split = splitOnce "=" param;
          in
          nameValuePair (unquoteURL split.before) (
            unquoteURL (if split.after != null then split.after else "")
          )
        ) (filter (param: param != "") (splitString "&" query))
      );

  isGitHash = value: match "[0-9a-fA-F]{7,40}" value != null;

  defaultGitRef = query: query.ref or (query.branch or (query.tag or (query.rev or null)));

  defaultFetchGitRef =
    query:
    query.ref or (
      if query ? branch then
        "refs/heads/${query.branch}"
      else if query ? tag then
        "refs/tags/${query.tag}"
      else if query ? rev && !(isGitHash query.rev) then
        query.rev
      else
        null
    );

  defaultLockedGitRev =
    gitSource:
    if gitSource.fragment != "" then
      gitSource.fragment
    else if gitSource.query ? rev && isGitHash gitSource.query.rev then
      gitSource.query.rev
    else
      null;

  stripAuthorityUserInfo =
    authority:
    let
      parts = splitString "@" authority;
    in
    elemAt parts ((length parts) - 1);

  encodePathSegmentSlashes = value: replaceStrings [ "/" ] [ "%2F" ] value;

  normalizeGitPath =
    path:
    let
      normalizedPath = removeSuffix ".git" (removeSuffix "/" path);
      segments = filter (segment: segment != "") (splitString "/" normalizedPath);
    in
    if normalizedPath == "" || segments == [ ] then
      null
    else
      {
        path = normalizedPath;
        inherit segments;
      };

  normalizeForcedGitRepo =
    value:
    let
      split = splitOnce "/" value;
      pathInfo = if split.after != null then normalizeGitPath split.after else null;
    in
    if split.after == null || split.before == "" || pathInfo == null then
      null
    else
      "${toLower split.before}/${pathInfo.path}";

  parseGitRemoteWithScheme =
    scheme: rest:
    let
      authoritySplit = splitOnce "/" rest;
    in
    if
      !elem scheme [
        "http"
        "https"
        "ssh"
        "git"
      ]
      || authoritySplit.after == null
      || authoritySplit.before == ""
    then
      null
    else
      {
        authority = authoritySplit.before;
        path = authoritySplit.after;
      };

in
rec {
  inherit unquoteURL;

  defaultGitForgeHosts = {
    "github.com" = "github";
    "gitlab.com" = "gitlab";
    "git.sr.ht" = "sourcehut";
  };

  parseForgeProject =
    forge: segments:
    if forge == "github" || forge == "sourcehut" then
      if length segments != 2 then
        null
      else
        {
          owner = head segments;
          repo = elemAt segments 1;
        }
    else if forge == "gitlab" then
      if length segments < 2 then
        null
      else
        {
          owner = encodePathSegmentSlashes (
            concatStringsSep "/" (builtins.genList (i: elemAt segments i) ((length segments) - 1))
          );
          repo = elemAt segments ((length segments) - 1);
        }
    else
      null;

  parseGitSource =
    source:
    let
      strippedSource = stripGitTransportPrefix source;
      fragmentSplit = splitOnce "#" strippedSource;
      querySplit = splitOnce "?" fragmentSplit.before;
      gitSource = {
        url = querySplit.before;
        query = parseURLQuery querySplit.after;
        fragment = unquoteURL (if fragmentSplit.after != null then fragmentSplit.after else "");
      };
    in
    gitSource
    // {
      lockedRev = defaultLockedGitRev gitSource;
      fetchGitRef = defaultFetchGitRef gitSource.query;
      fetchTreeRef = defaultGitRef gitSource.query;
    };

  parseGitRemote =
    url:
    let
      schemeSplit = splitOnce "://" url;
      mScp = match "([^@/:]+@)?([^:/]+):(.+)" url;

      parsed =
        if schemeSplit.after != null then
          parseGitRemoteWithScheme (toLower schemeSplit.before) schemeSplit.after
        else if mScp != null then
          {
            authority = elemAt mScp 1;
            path = elemAt mScp 2;
          }
        else
          null;
    in
    if parsed == null then
      null
    else
      let
        authorityWithoutUser = stripAuthorityUserInfo parsed.authority;
        authorityParts = splitString ":" authorityWithoutUser;
        host = head authorityParts;
        pathInfo = normalizeGitPath parsed.path;
      in
      if authorityWithoutUser == "" || pathInfo == null then
        null
      else
        {
          authority = toLower authorityWithoutUser;
          inherit host;
          hostLower = toLower host;
          hasPort = length authorityParts > 1;
          inherit (pathInfo) path segments;
        };

  selectGitFetcher =
    {
      config,
      hasFetchTree ? false,
    }:
    gitSource:
    let
      gitFetcher = config.git-fetcher or "git";
      gitForgeHosts = defaultGitForgeHosts // (config.git-forge-hosts or { });
      gitFetcherForceGit = map normalizeForcedGitRepo (config.git-fetcher-force-git or [ ]);
      parsed = parseGitRemote gitSource.url;
      normalizedRepo = if parsed != null then "${parsed.hostLower}/${parsed.path}" else null;
      forcedGit = normalizedRepo != null && elem normalizedRepo gitFetcherForceGit;
      fetchGitArgs = {
        inherit (gitSource) url;
      }
      // optionalAttrs (gitSource.lockedRev != null) { rev = gitSource.lockedRev; }
      // optionalAttrs (gitSource.fetchGitRef != null) { ref = gitSource.fetchGitRef; }
      // optionalAttrs (versionAtLeast nixVersion "2.4") {
        allRefs = true;
        submodules = true;
      };
      forge =
        if parsed != null && !parsed.hasPort then
          gitForgeHosts.${parsed.hostLower} or gitForgeHosts.${parsed.host} or null
        else
          null;
      defaultHost =
        if forge == "github" then
          "github.com"
        else if forge == "gitlab" then
          "gitlab.com"
        else if forge == "sourcehut" then
          "git.sr.ht"
        else
          null;
      hostAttrs = optionalAttrs (forge != null && parsed.hostLower != defaultHost) {
        host = parsed.hostLower;
      };
      project = if forge != null then parseForgeProject forge parsed.segments else null;
      fallback = {
        fetcher = "fetchGit";
        args = fetchGitArgs;
      };
    in
    if gitFetcher != "auto" || forcedGit || !hasFetchTree || parsed == null || forge == null then
      fallback
    else if project == null then
      fallback
    else
      {
        fetcher = "fetchTree";
        args = {
          type = forge;
          inherit (project) owner repo;
        }
        // optionalAttrs (gitSource.lockedRev != null) { rev = gitSource.lockedRev; }
        // optionalAttrs (gitSource.lockedRev == null && gitSource.fetchTreeRef != null) {
          ref = gitSource.fetchTreeRef;
        }
        // hostAttrs;
      };
}
