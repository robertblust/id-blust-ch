# ZITADEL's login v2 at the release infra/variables.tf names, with one row of its layout changed.
# ZITADEL's layout makes the row of the language and theme switchers as wide as the card on a
# phone and, from the md breakpoint, as wide as the page's 1100px container, while the card stays
# 440px, so on a desktop the switchers sit at the window's edge, apart from the card. Here the row
# keeps its phone width at every size and ends where the card ends. The row's classes are in the
# server-rendered layout once, and the build fails unless it finds them exactly once and changes
# them, so a release that moves them stops the build rather than shipping the row unchanged.
ARG ZITADEL_VERSION
FROM ghcr.io/zitadel/zitadel-login:${ZITADEL_VERSION}
LABEL org.opencontainers.image.source=https://github.com/robertblust/id-blust-ch
RUN set -eu; \
  row='justify-end space-x-4 px-4 py-4 md:max-w-full md:px-8"'; \
  files=$(grep -rlF "$row" apps/login/.next); \
  test "$(printf '%s\n' "$files" | grep -c .)" -eq 1; \
  sed -i 's/justify-end space-x-4 px-4 py-4 md:max-w-full md:px-8"/justify-end space-x-4 px-4 py-4"/' "$files"; \
  test -z "$(grep -lF "$row" "$files" || true)"; \
  grep -qF 'justify-end space-x-4 px-4 py-4"' "$files"
