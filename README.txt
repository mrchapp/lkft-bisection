cd /linux
git bisect start
git bisect old v5.0-rc7
git bisect new v5.0-rc8
git bisect run ~/lkft-bisection/bat.sh ~/lkft-bisection/simple-bisection.conf
