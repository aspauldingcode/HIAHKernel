#!/nix/store/p0k9r5h8qs7220xdbdihhfgzwjcly70x-bash-5.3p3/bin/bash
echo "$(git describe --tags --dirty="+" --match="v*" | sed -e 's@-\([^-]*\)-\([^-]*\)$@+\1.\2@;s@^v@2:@')"
