# Lab runtime configs

`php.ini` and `apache.conf` are local, Git-ignored files. On the first
container start, `entrypoint.sh` copies them from the tracked
`php.ini.template` and `apache.conf.template` files if they do not exist.

Edit `php.ini` and `apache.conf` for the Lab, but do not commit them; the
templates are the baseline that a fresh clone receives.
