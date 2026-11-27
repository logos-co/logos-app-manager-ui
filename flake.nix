{
  description = "App Manager: browse, install, upgrade and remove Logos apps";

  inputs = {
    logos-module-builder.url = "github:logos-co/logos-module-builder";

    package_manager.url = "github:logos-co/logos-package-manager-module";
    package_downloader.url = "github:logos-co/logos-package-downloader-module";

    # Headers only: <logos/semver.hpp>, the version order the library's row
    # rules use. Nothing here links liblgx.
    logos-package.url = "github:logos-co/logos-package";

    # Compiled in: the rows, filters, catalog client and install pipeline both
    # installer apps share. src/qml/Installer is a copy of its JavaScript; the
    # shared-installer-words check keeps it this revision.
    basecamp-installer-common = {
      url = "github:logos-co/basecamp-installer-common";
      inputs.logos-nix.follows = "logos-module-builder/logos-nix";
      inputs.logos-package.follows = "logos-package";
    };

    # intents_module's contract, contracts/intents.lidl: the backend asks
    # Basecamp's consent through it. Only the contract is read.
    logos-intents-module = {
      url = "github:logos-co/logos-intents-module";
      flake = false;
    };
  };

  outputs = inputs@{ logos-module-builder, logos-package, basecamp-installer-common, ... }:
    let
      shared = {
        src = ./.;
        configFile = ./metadata.json;
        flakeInputs = inputs;

        # `headers`: the backend includes logos/semver.hpp and links no lgx.
        externalLibInputs = {
          lgx = {
            input = logos-package;
            packages.default = "headers";
          };
        };

        # The library and the semver headers, staged where CMakeLists.txt
        # looks. Copied whole: the builder's own staging flattens include/.
        preConfigure = { externalLibs }: ''
          rm -rf vendor
          mkdir -p vendor/basecamp-installer-common
          cp -r ${externalLibs.lgx}/include/logos vendor/
          cp -r ${externalLibs.lgx}/include/semver vendor/
          cp -r ${basecamp-installer-common}/include ${basecamp-installer-common}/src \
                ${basecamp-installer-common}/cmake vendor/basecamp-installer-common/
          chmod -R u+w vendor
        '';
      };

      module = logos-module-builder.lib.mkLogosQmlModule shared;

      lib = logos-module-builder.inputs.nixpkgs.lib;
      systems = [ "aarch64-darwin" "x86_64-darwin" "aarch64-linux" "x86_64-linux" ];
      pkgsFor = system: import logos-module-builder.inputs.nixpkgs { inherit system; };

      checksFor = system:
        let pkgs = pkgsFor system;
        in {
          # The backend's logic on the library, with fake package modules and
          # a fake Basecamp (tests/cpp).
          unit-tests = pkgs.stdenv.mkDerivation {
            name = "logos-app-manager-ui-unit-tests";
            src = ./.;
            cmakeDir = "../tests";
            nativeBuildInputs = [ pkgs.cmake pkgs.ninja ];
            # ICU: the library's trust sources.
            buildInputs = [ pkgs.qt6.qtbase pkgs.icu ];
            dontWrapQtApps = true;
            cmakeFlags = [
              "-DBASECAMP_INSTALLER_COMMON_DIR=${basecamp-installer-common}"
              "-DLOGOS_PACKAGE_INCLUDE_DIR=${logos-package.packages.${system}.headers}/include"
            ];
            QT_QPA_PLATFORM = "offscreen";
            # The sandbox has no network to ask about.
            BASECAMP_FORCE_OFFLINE = "0";
            doCheck = true;
            checkPhase = "ctest --output-on-failure --verbose";
            installPhase = "touch $out";
          };

          # src/qml/Installer is the pinned library's JavaScript, and no screen
          # writes out a phrase it says.
          shared-installer-words = pkgs.runCommand "logos-app-manager-ui-shared-installer-words" {
            nativeBuildInputs = [ pkgs.python3 ];
          } ''
            cd ${./.}
            diff -r ${basecamp-installer-common}/qml/Installer src/qml/Installer \
              || { echo "src/qml/Installer is not the pinned basecamp-installer-common: run scripts/sync-installer-common.sh"; exit 1; }
            python3 ${basecamp-installer-common}/tools/shared-words-check \
              ${basecamp-installer-common}/qml/Installer src/qml \
              --skip src/qml/Installer --allow tests/shared-words-allow.txt
            touch $out
          '';
        };

      # The views' QML tests (tests/qml), from a phone's width to a desktop's:
      # qmltestrunner, offscreen, with a stand-in for the backend
      # (tests/qml/FakeBackend.qml). They run on the design system Basecamp's
      # master pins, read from its lock at run time: an app, as the Nix
      # sandbox cannot fetch Basecamp. LOGOS_BASECAMP names another Basecamp,
      # LOGOS_DESIGN_SYSTEM a design-system checkout to run on instead;
      # arguments pass to qmltestrunner.
      qmlTests = system:
        let
          pkgs = pkgsFor system;
          qml = pkgs.qt6.qtdeclarative;
          plugins = pkgs.qt6.qtbase.qtPluginPrefix;
          pinOf = pkgs.writeText "design-system-pin.jq" ''
            .locks.nodes as $n | $n[$n.root.inputs["logos-design-system"]].locked
            | "\(.type):\(.owner)/\(.repo)/\(.rev)"
          '';
          run = pkgs.writeShellApplication {
            name = "run-qml-tests";
            runtimeInputs = [ pkgs.jq ];
            text = ''
              ds="''${LOGOS_DESIGN_SYSTEM:-}"
              if [ -z "$ds" ]; then
                ref="''${LOGOS_BASECAMP:-github:logos-co/logos-basecamp}"
                pin=$(nix flake metadata "$ref" --json | jq -r -f ${pinOf})
                echo "run-qml-tests: on the design system $ref pins, $pin" >&2
                ds=$(nix flake prefetch "$pin" --json | jq -r .storePath)
              fi
              export QT_QPA_PLATFORM=offscreen
              export QT_QUICK_CONTROLS_STYLE="''${QT_QUICK_CONTROLS_STYLE:-Basic}"
              export QT_PLUGIN_PATH="${pkgs.qt6.qtbase}/${plugins}:${pkgs.qt6.qtsvg}/${plugins}"
              exec ${qml}/bin/qmltestrunner \
                -input ${./.}/tests/qml \
                -import ${./.}/src/qml \
                -import "$ds/src/qml" \
                -import ${qml}/${pkgs.qt6.qtbase.qtQmlPrefix} "$@"
            '';
          };
        in { type = "app"; program = "${run}/bin/run-qml-tests"; };
    in
    module // {
      checks = lib.genAttrs systems
        (system: ((module.checks or { }).${system} or { }) // checksFor system);
      apps = builtins.mapAttrs
        (system: apps: apps
          // (if system == "x86_64-windows" then { } else { qml-tests = qmlTests system; }))
        module.apps;
    };
}
