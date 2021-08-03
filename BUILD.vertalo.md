git clone git@github.com:vertalo/tezos
cd tezos
git checkout v9-release-freebsd
gmake -f Makefile.vertalo init
gmake -f Makefile.vertalo build-deps
gmake -f Makefile.vertalo upgrade-jbuilder
gmake -f Makefile.vertalo install-lmdb
gmake -f Makefile.vertalo all

# not yet working on this branch, but does work
# with 9.4 from gitlab.com:tezos/tezos
gmake -f Makefile.vertalo test

