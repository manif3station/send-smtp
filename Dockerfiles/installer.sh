#!/bin/sh
HOME=/tmp cpanm --notest --installdeps .
rm -fr /tmp/.cpamn
