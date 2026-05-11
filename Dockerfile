FROM ubuntu:20.04
LABEL maintainer="sysadmin@axsmarine.com"

#Target the Bulgarian Ubuntu archive repo
RUN sed -i "s|:\/\/archive|:\/\/bg.archive|g" /etc/apt/sources.list

#NEEDED AS TZDATA configure is now interactive
RUN export DEBIAN_FRONTEND=noninteractive && apt-get update && apt-get install -y tzdata apt-transport-https gnupg ca-certificates

# add our user and group first to make sure their IDs get assigned consistently, regardless of whatever dependencies get added
RUN groupadd -r -g 1000 axsmarine && useradd -r -g axsmarine -u 1000 axsmarine

# grab gosu for easy step-down from root
# https://github.com/tianon/gosu/releases
ENV GOSU_VERSION 1.14

RUN set -eux; \
        savedAptMark="$(apt-mark showmanual)"; \
        apt-get update; \
        apt-get install -y --no-install-recommends dirmngr wget; \
        rm -rf /var/lib/apt/lists/*; \
        dpkgArch="$(dpkg --print-architecture | awk -F- '{ print $NF }')"; \
        wget -O /usr/local/bin/gosu "https://github.com/tianon/gosu/releases/download/$GOSU_VERSION/gosu-$dpkgArch"; \
        wget -O /usr/local/bin/gosu.asc "https://github.com/tianon/gosu/releases/download/$GOSU_VERSION/gosu-$dpkgArch.asc"; \
        export GNUPGHOME="$(mktemp -d)"; \
        gpg --batch --keyserver hkps://keys.openpgp.org --recv-keys B42F6819007F00F88E364FD4036A9C25BF357DD4; \
        gpg --batch --verify /usr/local/bin/gosu.asc /usr/local/bin/gosu; \
        gpgconf --kill all; \
        rm -rf "$GNUPGHOME" /usr/local/bin/gosu.asc; \
        apt-mark auto '.*' > /dev/null; \
        [ -z "$savedAptMark" ] || apt-mark manual $savedAptMark > /dev/null; \
        apt-get purge -y --auto-remove -o APT::AutoRemove::RecommendsImportant=false; \
        chmod +x /usr/local/bin/gosu; \
        gosu --version; \
        gosu nobody true

# ensure local python is preferred over distribution python
ENV PATH /usr/local/bin:$PATH
ENV GPG_KEY A035C8C19219BA821ECEA86B64E628F8D684696D
ENV PYTHON_VERSION 3.10.11

# http://bugs.python.org/issue19846
# > At the moment, setting "LANG=C" on a Linux system *fundamentally breaks Python 3*, and that's not OK.
ENV LANG C.UTF-8

#Add gpg key
COPY ./etc/apt/axs-aptly-repo.list /etc/apt/sources.list.d
COPY ./etc/apt/AXS_apt-repositories.gpg /etc/apt/trusted.gpg.d

# FileBeat source and key
COPY ./etc/apt/elastic-7.x.list /etc/apt/sources.list.d
COPY ./etc/apt/GPG-KEY-elasticsearch /tmp

# Add FileBeat key
RUN apt-key add /tmp/GPG-KEY-elasticsearch && rm /tmp/GPG-KEY-elasticsearch

#Clean after
RUN apt-get clean && rm -rf /var/lib/apt/lists/*

# build python 3.10
RUN set -eux; \
	\
	savedAptMark="$(apt-mark showmanual)"; \
	apt-get update; \
	apt-get install -y --no-install-recommends autoconf automake bzip2 dpkg-dev file g++ gcc imagemagick libbz2-dev libc6-dev libcurl4-openssl-dev libdb-dev libevent-dev libffi-dev libgdbm-dev libglib2.0-dev libgmp-dev libjpeg-dev libkrb5-dev liblzma-dev libmagickcore-dev libmagickwand-dev libmaxminddb-dev libncurses5-dev libncursesw5-dev libpng-dev libpq-dev libreadline-dev libsqlite3-dev libssl-dev libtool libwebp-dev libxml2-dev libxslt-dev libyaml-dev make patch unzip xz-utils zlib1g-dev wget; \
        wget -O python.tar.xz "https://www.python.org/ftp/python/${PYTHON_VERSION%%[a-z]*}/Python-$PYTHON_VERSION.tar.xz"; \
	wget -O python.tar.xz.asc "https://www.python.org/ftp/python/${PYTHON_VERSION%%[a-z]*}/Python-$PYTHON_VERSION.tar.xz.asc"; \
	GNUPGHOME="$(mktemp -d)"; export GNUPGHOME; \
	gpg --batch --keyserver hkps://keys.openpgp.org --recv-keys "$GPG_KEY"; \
	gpg --batch --verify python.tar.xz.asc python.tar.xz; \
	command -v gpgconf > /dev/null && gpgconf --kill all || :; \
	rm -rf "$GNUPGHOME" python.tar.xz.asc; \
	mkdir -p /usr/src/python; \
	tar --extract --directory /usr/src/python --strip-components=1 --file python.tar.xz; \
	rm python.tar.xz; \
	\
	cd /usr/src/python; \
	gnuArch="$(dpkg-architecture --query DEB_BUILD_GNU_TYPE)"; \
        ./configure \
		--build="$gnuArch" \
		--enable-loadable-sqlite-extensions \
		--enable-optimizations \
		--enable-option-checking=fatal \
		--enable-shared \
		--with-lto \
		--with-system-expat \
		--without-ensurepip \
	; \
	nproc="$(nproc)"; \
        EXTRA_CFLAGS="$(dpkg-buildflags --get CFLAGS)"; \
	LDFLAGS="$(dpkg-buildflags --get LDFLAGS)"; \
        make -j "$nproc" \
		"EXTRA_CFLAGS=${EXTRA_CFLAGS:-}" \
		"LDFLAGS=${LDFLAGS:-}" \
		"PROFILE_TASK=${PROFILE_TASK:-}" \
	; \
        # https://github.com/docker-library/python/issues/784
        # prevent accidental usage of a system installed libpython of the same version
	rm python; \
	make -j "$nproc" \
		"EXTRA_CFLAGS=${EXTRA_CFLAGS:-}" \
		"LDFLAGS=${LDFLAGS:--Wl},-rpath='\$\$ORIGIN/../lib'" \
		"PROFILE_TASK=${PROFILE_TASK:-}" \
		python \
	; \
	make install; \
	\
        # enable GDB to load debugging data: https://github.com/docker-library/python/pull/701
	bin="$(readlink -ve /usr/local/bin/python3)"; \
	dir="$(dirname "$bin")"; \
	mkdir -p "/usr/share/gdb/auto-load/$dir"; \
	cp -vL Tools/gdb/libpython.py "/usr/share/gdb/auto-load/$bin-gdb.py"; \
	\
	cd /; \
	rm -rf /usr/src/python; \
	\
	find /usr/local -depth \
		\( \
			\( -type d -a \( -name test -o -name tests -o -name idle_test \) \) \
			-o \( -type f -a \( -name '*.pyc' -o -name '*.pyo' -o -name 'libpython*.a' \) \) \
			-o \( -type f -a -name 'wininst-*.exe' \) \
		\) -exec rm -rf '{}' + \
	; \
	\
	ldconfig; \
	\
	apt-mark auto '.*' > /dev/null; \
	apt-mark manual $savedAptMark; \
	find /usr/local -type f -executable -not \( -name '*tkinter*' \) -exec ldd '{}' ';' \
		| awk '/=>/ { print $(NF-1) }' \
		| sort -u \
		| xargs -r dpkg-query --search \
		| cut -d: -f1 \
		| sort -u \
		| xargs -r apt-mark manual \
	; \
	apt-get purge -y --auto-remove -o APT::AutoRemove::RecommendsImportant=false; \
	rm -rf /var/lib/apt/lists/*; \
	\
	python3 --version

# make some useful symlinks that are expected to exist ("/usr/local/bin/python" and friends)
RUN set -eux; \
	for src in idle3 pydoc3 python3 python3-config; do \
		dst="$(echo "$src" | tr -d 3)"; \
		[ -s "/usr/local/bin/$src" ]; \
		[ ! -e "/usr/local/bin/$dst" ]; \
		ln -svT "$src" "/usr/local/bin/$dst"; \
	done

# if this is called "PIP_VERSION", pip explodes with "ValueError: invalid truth value '<VERSION>'"
ENV PYTHON_PIP_VERSION 23.0.1
# https://github.com/docker-library/python/issues/365
ENV PYTHON_SETUPTOOLS_VERSION 65.5.1
# https://github.com/pypa/get-pip
ENV PYTHON_GET_PIP_URL https://github.com/pypa/get-pip/raw/2b873b978dbfdfc5e15ef5c3adf4354084612432/public/get-pip.py
ENV PYTHON_GET_PIP_SHA256 1d353ebfe0e669c7fce28bc2e4ea802dfeef4c09c170295c15c902714520991a

RUN set -eux; \
	\
	savedAptMark="$(apt-mark showmanual)"; \
	apt-get update; \
	apt-get install -y --no-install-recommends wget; \
	\
	wget -O get-pip.py "$PYTHON_GET_PIP_URL"; \
	echo "$PYTHON_GET_PIP_SHA256 *get-pip.py" | sha256sum -c -; \
	\
	apt-mark auto '.*' > /dev/null; \
	[ -z "$savedAptMark" ] || apt-mark manual $savedAptMark > /dev/null; \
	apt-get purge -y --auto-remove -o APT::AutoRemove::RecommendsImportant=false; \
	rm -rf /var/lib/apt/lists/*; \
	\
	export PYTHONDONTWRITEBYTECODE=1; \
	\
	python get-pip.py \
		--disable-pip-version-check \
		--no-cache-dir \
		--no-compile \
		"pip==$PYTHON_PIP_VERSION" \
		"setuptools==$PYTHON_SETUPTOOLS_VERSION" \
	; \
	rm -f get-pip.py; \
	\
	pip --version

RUN apt-get update \
 && apt-get install -y --no-install-recommends wget ca-certificates \
 && wget https://packages.graylog2.org/repo/packages/graylog-sidecar-repository_1-2_all.deb \
 && dpkg -i graylog-sidecar-repository_1-2_all.deb \
 && rm graylog-sidecar-repository_1-2_all.deb \
 && apt-get update \
 && apt-get install -y --no-install-recommends supervisor graylog-sidecar filebeat \
 && rm -rf /var/lib/apt/lists/*

# Add FileBeat config
COPY ./etc/graylog-sidecar/sidecar.yml /etc/graylog/sidecar

#Copy supervisor config
COPY ./etc/supervisor/supervisord.conf /etc/supervisor/supervisord.conf

#next lines are supervisord hacks
ENV env ''

RUN service supervisor stop
RUN update-rc.d -f supervisor remove
RUN rm /etc/init.d/supervisor

COPY ./sbin/set-env.sh /sbin/set-env.sh
RUN chmod +x /sbin/set-env.sh

COPY ./sbin/start-python.sh /sbin/start-python.sh
RUN chmod +x /sbin/start-python.sh

# Create axsmarine general log file
RUN touch /var/log/axsmarine-general.log && chmod o+rw /var/log/axsmarine-general.log

# Create axsmarine audit log file
RUN touch /var/log/axsmarine-audit.log && chmod o+rw /var/log/axsmarine-audit.log

CMD ["/usr/bin/supervisord", "-n", "-c", "/etc/supervisor/supervisord.conf", "-j", "/var/run/supervisord.pid"]
