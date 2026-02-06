# Maintainer: TheKrystalShip <contact@thekrystalship.com>
pkgname=kgsm
pkgver=3.0.0
pkgrel=1
pkgdesc="Krystal Game Server Manager - Game server orchestration for Linux"
arch=('any')
url="https://github.com/TheKrystalShip/KGSM"
license=('GPL-3.0-or-later')
depends=(
  'bash>=5.0'
  'coreutils'
  'grep'
  'sed'
  'curl'
  'jq'
  'findutils'
)
optdepends=(
  'steamcmd: Steam-based game server support'
  'lib32-gcc-libs: Required by some Steam servers'
  'ufw: Automatic firewall rule management'
  'docker: Container-based game servers'
  'docker-compose: Docker Compose support'
)
source=("${pkgname}-${pkgver}.tar.gz::https://github.com/TheKrystalShip/KGSM/archive/refs/tags/v${pkgver}.tar.gz")
sha256sums=('SKIP')  # Replace with actual checksum

package() {
  cd "KGSM-${pkgver}"

  # Create directories
  install -dm755 "$pkgdir/usr/share/kgsm"
  install -dm755 "$pkgdir/usr/share/doc/kgsm"
  install -dm755 "$pkgdir/usr/share/licenses/kgsm"

  # Install main script
  install -Dm755 kgsm.sh "$pkgdir/usr/share/kgsm/kgsm.sh"

  # Install core modules
  install -dm755 "$pkgdir/usr/share/kgsm/core"
  install -Dm644 core/*.sh "$pkgdir/usr/share/kgsm/core/"

  # Install command modules
  install -dm755 "$pkgdir/usr/share/kgsm/commands"
  install -Dm644 commands/*.sh "$pkgdir/usr/share/kgsm/commands/"

  # Install command handlers
  install -dm755 "$pkgdir/usr/share/kgsm/commands/handlers"
  install -Dm644 commands/handlers/*.sh "$pkgdir/usr/share/kgsm/commands/handlers/"

  # Install templates
  install -dm755 "$pkgdir/usr/share/kgsm/templates"
  install -Dm644 templates/* "$pkgdir/usr/share/kgsm/templates/"

  # Install default overrides
  install -dm755 "$pkgdir/usr/share/kgsm/overrides"
  install -Dm644 overrides/*.sh "$pkgdir/usr/share/kgsm/overrides/"

  # Install migrations
  if [[ -d migrations/config ]]; then
    install -dm755 "$pkgdir/usr/share/kgsm/migrations/config"
    install -Dm644 migrations/config/* "$pkgdir/usr/share/kgsm/migrations/config/" 2>/dev/null || true
  fi

  # Install default blueprints (native)
  install -dm755 "$pkgdir/usr/share/kgsm/blueprints/native/default"
  if [[ -d blueprints/native/default ]]; then
    install -Dm644 blueprints/native/default/* "$pkgdir/usr/share/kgsm/blueprints/native/default/"
  fi

  # Install default blueprints (container)
  install -dm755 "$pkgdir/usr/share/kgsm/blueprints/container/default"
  if [[ -d blueprints/container/default ]]; then
    install -Dm644 blueprints/container/default/* "$pkgdir/usr/share/kgsm/blueprints/container/default/" 2>/dev/null || true
  fi

  # Install default config
  install -Dm644 config.default.ini "$pkgdir/usr/share/kgsm/config.default.ini"

  # Install documentation
  install -Dm644 README.md "$pkgdir/usr/share/doc/kgsm/README.md"
  install -Dm644 CHANGELOG.md "$pkgdir/usr/share/doc/kgsm/CHANGELOG.md"
  if [[ -d docs ]]; then
    cp -r docs "$pkgdir/usr/share/doc/kgsm/"
  fi

  # Install license
  install -Dm644 LICENSE "$pkgdir/usr/share/licenses/kgsm/LICENSE"

  # Create symlink for /usr/bin/kgsm
  install -dm755 "$pkgdir/usr/bin"
  ln -sf /usr/share/kgsm/kgsm.sh "$pkgdir/usr/bin/kgsm"
}
