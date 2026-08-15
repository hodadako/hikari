#!/bin/zsh
set -euo pipefail

script_directory="${0:A:h}"
repository_root="${script_directory:h}"
timestamp="$(date +%Y%m%d-%H%M%S)"
build_architecture="$(uname -m)"
deployment_target="${build_architecture}-apple-macosx15.0"
output_root="${1:-${repository_root}/.personal/build/native-local-${timestamp}}"
module_directory="${output_root}/Modules"
library_directory="${output_root}/Libraries"
app_name="Hikari"
app_path="${output_root}/${app_name}.app"
resource_path="${app_path}/Contents/Resources"
iconset_path="${output_root}/LuminaNativeIcon.iconset"
install_directory="${LUMINA_NATIVE_INSTALL_DIRECTORY:-/Applications}"
installed_app_path="${install_directory}/${app_name}.app"
install_staging_path="${install_directory}/.${app_name}.app.installing.$$"

cleanup_install_staging() {
  if [[ -n "${install_staging_path}" && -e "${install_staging_path}" ]]; then
    rm -rf "${install_staging_path}"
  fi
}
trap cleanup_install_staging EXIT

if [[ -e "${app_path}" ]]; then
  print -u2 "Refusing to overwrite existing app: ${app_path}"
  exit 1
fi

mkdir -p \
  "${module_directory}" \
  "${library_directory}" \
  "${app_path}/Contents/MacOS" \
  "${resource_path}" \
  "${iconset_path}"

cd "${repository_root}"

swiftc \
  -parse-as-library \
  -emit-module \
  -emit-library \
  -static \
  -module-name LuminaCore \
  -target "${deployment_target}" \
  Sources/LuminaCore/*.swift \
  -emit-module-path "${module_directory}/LuminaCore.swiftmodule" \
  -o "${library_directory}/libLuminaCore.a"

swiftc \
  -parse-as-library \
  -emit-module \
  -emit-library \
  -static \
  -module-name LuminaNativeLock \
  -target "${deployment_target}" \
  Sources/LuminaNativeLock/*.swift \
  -emit-module-path "${module_directory}/LuminaNativeLock.swiftmodule" \
  -o "${library_directory}/libLuminaNativeLock.a"

swiftc \
  -parse-as-library \
  -target "${deployment_target}" \
  -I "${module_directory}" \
  -L "${library_directory}" \
  -lLuminaNativeLock \
  Sources/LuminaNativeTool/*.swift \
  -o "${app_path}/Contents/MacOS/lumina-native-tool"

swiftc \
  -parse-as-library \
  -D LUMINA_NATIVE_LOCAL \
  -target "${deployment_target}" \
  -I "${module_directory}" \
  -L "${library_directory}" \
  -lLuminaCore \
  -lLuminaNativeLock \
  Sources/LuminaApp/*.swift \
  -o "${app_path}/Contents/MacOS/${app_name}"

ditto Resources/LuminaNative-Info.plist "${app_path}/Contents/Info.plist"
hikari_marketing_version="$(awk '/HIKARI_MARKETING_VERSION:/ { print $2; exit }' project.yml)"
hikari_build_number="$(awk '/HIKARI_BUILD_NUMBER:/ { print $2; exit }' project.yml)"
if [[ ! "${hikari_marketing_version}" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
  print -u2 "Invalid HIKARI_MARKETING_VERSION in project.yml"
  exit 1
fi
if [[ ! "${hikari_build_number}" =~ ^[0-9]+$ ]]; then
  print -u2 "Invalid HIKARI_BUILD_NUMBER in project.yml"
  exit 1
fi
plutil -replace CFBundleDevelopmentRegion -string en "${app_path}/Contents/Info.plist"
plutil -replace CFBundleExecutable -string "${app_name}" "${app_path}/Contents/Info.plist"
plutil -replace CFBundleDisplayName -string "${app_name}" "${app_path}/Contents/Info.plist"
plutil -replace CFBundleName -string "${app_name}" "${app_path}/Contents/Info.plist"
plutil -replace CFBundleIdentifier -string com.hodadako.Lumina.NativeLocal "${app_path}/Contents/Info.plist"
plutil -replace CFBundleShortVersionString -string "${hikari_marketing_version}" "${app_path}/Contents/Info.plist"
plutil -replace CFBundleVersion -string "${hikari_build_number}" "${app_path}/Contents/Info.plist"
plutil -replace LSMinimumSystemVersion -string 15.0 "${app_path}/Contents/Info.plist"
plutil -insert CFBundleIconFile -string AppIcon "${app_path}/Contents/Info.plist"

ditto Resources/en.lproj "${resource_path}/en.lproj"
ditto Resources/ko.lproj "${resource_path}/ko.lproj"
ditto Resources/Assets.xcassets/LuminaIconDefault.imageset/lumina_new_icon.png \
  "${resource_path}/LuminaIconDefault.png"
ditto Resources/Assets.xcassets/MenuBarIconLumina.imageset/lumina_menu_bar_icon.png \
  "${resource_path}/MenuBarIconLumina.png"
ditto Resources/Assets.xcassets/MenuBarIconHeartbeat.imageset/lumina_menu_bar_icon_heartbeat.png \
  "${resource_path}/MenuBarIconHeartbeat.png"

for icon_file in \
  icon_16x16.png icon_16x16@2x.png \
  icon_32x32.png icon_32x32@2x.png \
  icon_128x128.png icon_128x128@2x.png \
  icon_256x256.png icon_256x256@2x.png \
  icon_512x512.png icon_512x512@2x.png
do
  ditto \
    "Resources/Assets.xcassets/AppIcon.appiconset/${icon_file}" \
    "${iconset_path}/${icon_file}"
done
iconutil --convert icns "${iconset_path}" --output "${resource_path}/AppIcon.icns"

codesign --force --deep --sign - "${app_path}"
codesign --verify --deep --strict "${app_path}"

mkdir -p "${install_directory}"
rm -rf "${install_staging_path}"
ditto "${app_path}" "${install_staging_path}"
codesign --verify --deep --strict "${install_staging_path}"
rm -rf "${installed_app_path}"
mv "${install_staging_path}" "${installed_app_path}"
install_staging_path=""
touch "${installed_app_path}"

launch_services_register="/System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister"
if [[ -x "${launch_services_register}" ]]; then
  "${launch_services_register}" -f "${installed_app_path}"
fi
mdimport "${installed_app_path}" >/dev/null 2>&1 || true

print "${installed_app_path}"
