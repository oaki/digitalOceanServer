# PHP sites run on PHP 8.3 via the ondrej/php PPA, one shared FPM pool

New PHP sites run PHP 8.3.33 installed from the `ondrej/php` PPA (not Ubuntu's
own distro package), sharing one FPM pool (`/etc/php/8.3/fpm/pool.d/www.conf`,
default settings) across every PHP site rather than a pool per site. This
decision only exists because the droplet is now Ubuntu 24.04 (noble) — on the
old droplet's Ubuntu 20.04 (focal), the same PPA publishes nothing at all
(confirmed by checking its raw package index: an empty `Packages` file for
every PHP version), which was one of the concrete reasons for migrating to a
new droplet rather than upgrading in place.

We chose one shared pool over a pool per site for lower memory overhead
(relevant on this droplet even after resizing to 2GB) — acceptable since
sites are low-traffic and don't need strict isolation from each other. A
site with different needs (its own PHP version, or isolation) would get its
own dedicated pool file instead; see `docs/deploying-a-php-site.md`.

Note: `ondrej/php`'s own description says it's being merged into
`packages.sury.org`, and that for whatever comes after noble (they name
"Resolute"), sury.org is the only supported source — this PPA already
doesn't publish anything past noble. Re-check this before adding PHP to any
future, newer droplet.
