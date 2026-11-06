ARG PHP_IMAGE=php:8.3.35-apache-bookworm
FROM ${PHP_IMAGE}

ARG MOODLE_VERSION=4.5.15

RUN set -eux; \
    apt-get update; \
    apt-get install -y --no-install-recommends \
        libfreetype6-dev libicu-dev libjpeg62-turbo-dev \
        libpng-dev libxml2-dev libzip-dev; \
    docker-php-ext-configure gd --with-freetype --with-jpeg; \
    docker-php-ext-install -j "$(nproc)" gd intl mysqli opcache \
        pdo_mysql soap zip; \
    a2enmod rewrite; \
    rm -rf /var/lib/apt/lists/*

RUN set -eux; \
    curl --fail --location --show-error --silent \
        "https://download.moodle.org/download.php/direct/stable405/moodle-${MOODLE_VERSION}.tgz" \
        -o /tmp/moodle.tgz; \
    tar -xzf /tmp/moodle.tgz --strip-components=1 -C /var/www/html; \
    rm /tmp/moodle.tgz; \
    grep -m1 '^\$release' /var/www/html/version.php || true; \
    mkdir -p /var/www/moodledata /var/www/config /opt/lab; \
    chown -R www-data:www-data /var/www/html /var/www/moodledata /var/www/config

COPY php-lab.ini /usr/local/etc/php/conf.d/zz-lab.ini
COPY entrypoint.sh /usr/local/bin/lab-entrypoint
COPY moodle-ui.php /usr/local/bin/lab-ui
RUN chmod +x /usr/local/bin/lab-entrypoint /usr/local/bin/lab-ui

ENTRYPOINT ["lab-entrypoint"]
CMD ["apache2-foreground"]

