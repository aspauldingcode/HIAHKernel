#!/nix/store/p0k9r5h8qs7220xdbdihhfgzwjcly70x-bash-5.3p3/bin/bash
dir=$1
dir=${dir:=_}
sed -e "s@^\(Version:.*\)@\1$(./version.sh)@" control
echo "Installed-Size: $(du -s "${dir}" | cut -f 1)"
