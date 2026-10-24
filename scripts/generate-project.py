#!/usr/bin/env python3
"""Regenerate the dependency-free Xcode project after adding/removing Swift files."""

from hashlib import sha256
from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]
PROJECT = ROOT / "FolioVoice.xcodeproj"
APP = ROOT / "FolioVoice"


def identifier(value):
    return sha256(value.encode()).hexdigest()[:24].upper()


def quoted(value):
    return '"' + str(value).replace('\\', '\\\\').replace('"', '\\"') + '"'


def build_settings(values):
    return "\n".join(f"\t\t\t\t{key} = {value};" for key, value in values.items())


def main():
    sources = sorted(APP.rglob("*.swift"))
    project_id = identifier("project")
    target_id = identifier("target")
    app_ref = identifier("product")
    asset_ref = identifier("assets-ref")
    asset_build = identifier("assets-build")
    plist_ref = identifier("plist-ref")
    sources_phase = identifier("sources-phase")
    resources_phase = identifier("resources-phase")
    frameworks_phase = identifier("frameworks-phase")
    main_group = identifier("main-group")
    app_group = identifier("app-group")
    product_group = identifier("product-group")
    project_configs = identifier("project-configs")
    target_configs = identifier("target-configs")

    records = [(path.relative_to(APP).as_posix(), path.name) for path in sources]
    file_refs = []
    build_files = []
    source_members = []
    app_children = []
    for relative, name in records:
        ref = identifier("file:" + relative)
        build = identifier("build:" + relative)
        file_refs.append(
            f"\t\t{ref} = {{isa = PBXFileReference; lastKnownFileType = sourcecode.swift; "
            f"name = {quoted(name)}; path = {quoted(relative)}; sourceTree = \"<group>\"; }};"
        )
        build_files.append(f"\t\t{build} = {{isa = PBXBuildFile; fileRef = {ref}; }};")
        source_members.append(f"\t\t\t\t{build},")
        app_children.append(f"\t\t\t\t{ref},")

    project_shared = {
        "ALWAYS_SEARCH_USER_PATHS": "NO",
        "CLANG_ENABLE_MODULES": "YES",
        "CLANG_ENABLE_OBJC_ARC": "YES",
        "CLANG_WARN_DOCUMENTATION_COMMENTS": "YES",
        "CLANG_WARN_QUOTED_INCLUDE_IN_FRAMEWORK_HEADER": "YES",
        "COPY_PHASE_STRIP": "NO",
        "ENABLE_STRICT_OBJC_MSGSEND": "YES",
        "GCC_C_LANGUAGE_STANDARD": "gnu17",
        "GCC_NO_COMMON_BLOCKS": "YES",
        "GCC_WARN_64_TO_32_BIT_CONVERSION": "YES",
        "GCC_WARN_ABOUT_RETURN_TYPE": "YES_ERROR",
        "GCC_WARN_UNDECLARED_SELECTOR": "YES",
        "GCC_WARN_UNINITIALIZED_AUTOS": "YES_AGGRESSIVE",
        "GCC_WARN_UNUSED_FUNCTION": "YES",
        "GCC_WARN_UNUSED_VARIABLE": "YES",
        "IPHONEOS_DEPLOYMENT_TARGET": "17.0",
        "SDKROOT": "iphoneos",
        "SWIFT_VERSION": "5.0",
    }
    target_shared = {
        "ASSETCATALOG_COMPILER_APPICON_NAME": "AppIcon",
        "ASSETCATALOG_COMPILER_GLOBAL_ACCENT_COLOR_NAME": "AccentColor",
        "CODE_SIGN_STYLE": "Automatic",
        "CURRENT_PROJECT_VERSION": "1",
        "DEVELOPMENT_TEAM": '""',
        "ENABLE_PREVIEWS": "YES",
        "GENERATE_INFOPLIST_FILE": "NO",
        "INFOPLIST_FILE": "FolioVoice/Info.plist",
        "LD_RUNPATH_SEARCH_PATHS": '("$(inherited)", "@executable_path/Frameworks")',
        "MARKETING_VERSION": "1.0",
        "PRODUCT_BUNDLE_IDENTIFIER": "com.atharv.FolioVoice",
        "PRODUCT_NAME": '"$(TARGET_NAME)"',
        "SUPPORTED_PLATFORMS": '"iphoneos iphonesimulator"',
        "SUPPORTS_MACCATALYST": "NO",
        "SUPPORTS_MAC_DESIGNED_FOR_IPHONE_IPAD": "NO",
        "SWIFT_EMIT_LOC_STRINGS": "YES",
        "TARGETED_DEVICE_FAMILY": "1",
    }
    configs = []
    for scope, base in [("project", project_shared), ("target", target_shared)]:
        for name in ["Debug", "Release"]:
            values = dict(base)
            if scope == "project":
                if name == "Debug":
                    values.update({
                        "DEBUG_INFORMATION_FORMAT": "dwarf",
                        "ENABLE_TESTABILITY": "YES",
                        "GCC_OPTIMIZATION_LEVEL": "0",
                        "GCC_PREPROCESSOR_DEFINITIONS": '("DEBUG=1", "$(inherited)")',
                        "ONLY_ACTIVE_ARCH": "YES",
                        "SWIFT_ACTIVE_COMPILATION_CONDITIONS": '"DEBUG $(inherited)"',
                        "SWIFT_OPTIMIZATION_LEVEL": '"-Onone"',
                    })
                else:
                    values.update({
                        "DEBUG_INFORMATION_FORMAT": '"dwarf-with-dsym"',
                        "SWIFT_COMPILATION_MODE": "wholemodule",
                        "SWIFT_OPTIMIZATION_LEVEL": '"-O"',
                        "VALIDATE_PRODUCT": "YES",
                    })
            configs.append(
                f"\t\t{identifier(scope + ':' + name)} = {{\n"
                f"\t\t\tisa = XCBuildConfiguration;\n\t\t\tbuildSettings = {{\n"
                f"{build_settings(values)}\n\t\t\t}};\n\t\t\tname = {name};\n\t\t}};"
            )

    output = f'''// !$*UTF8*$!
{{
    archiveVersion = 1;
    classes = {{}};
    objectVersion = 56;
    objects = {{
/* Begin PBXBuildFile section */
{chr(10).join(build_files)}
        {asset_build} = {{isa = PBXBuildFile; fileRef = {asset_ref}; }};
/* End PBXBuildFile section */

/* Begin PBXFileReference section */
{chr(10).join(file_refs)}
        {app_ref} = {{isa = PBXFileReference; explicitFileType = wrapper.application; includeInIndex = 0; path = FolioVoice.app; sourceTree = BUILT_PRODUCTS_DIR; }};
        {asset_ref} = {{isa = PBXFileReference; lastKnownFileType = folder.assetcatalog; path = Assets.xcassets; sourceTree = "<group>"; }};
        {plist_ref} = {{isa = PBXFileReference; lastKnownFileType = text.plist.xml; path = Info.plist; sourceTree = "<group>"; }};
/* End PBXFileReference section */

/* Begin PBXFrameworksBuildPhase section */
        {frameworks_phase} = {{isa = PBXFrameworksBuildPhase; buildActionMask = 2147483647; files = (); runOnlyForDeploymentPostprocessing = 0; }};
/* End PBXFrameworksBuildPhase section */

/* Begin PBXGroup section */
        {main_group} = {{isa = PBXGroup; children = ({app_group}, {product_group}); sourceTree = "<group>"; }};
        {app_group} = {{
            isa = PBXGroup;
            children = (
{chr(10).join(app_children)}
                {asset_ref},
                {plist_ref},
            );
            path = FolioVoice;
            sourceTree = "<group>";
        }};
        {product_group} = {{isa = PBXGroup; children = ({app_ref}); name = Products; sourceTree = "<group>"; }};
/* End PBXGroup section */

/* Begin PBXNativeTarget section */
        {target_id} = {{
            isa = PBXNativeTarget;
            buildConfigurationList = {target_configs};
            buildPhases = ({sources_phase}, {frameworks_phase}, {resources_phase});
            buildRules = ();
            dependencies = ();
            name = FolioVoice;
            productName = FolioVoice;
            productReference = {app_ref};
            productType = "com.apple.product-type.application";
        }};
/* End PBXNativeTarget section */

/* Begin PBXProject section */
        {project_id} = {{
            isa = PBXProject;
            attributes = {{
                BuildIndependentTargetsInParallel = 1;
                LastSwiftUpdateCheck = 1600;
                LastUpgradeCheck = 1600;
                TargetAttributes = {{
                    {target_id} = {{CreatedOnToolsVersion = 16.0; }};
                }};
            }};
            buildConfigurationList = {project_configs};
            compatibilityVersion = "Xcode 14.0";
            developmentRegion = en;
            hasScannedForEncodings = 0;
            knownRegions = (en, Base);
            mainGroup = {main_group};
            productRefGroup = {product_group};
            projectDirPath = "";
            projectRoot = "";
            targets = ({target_id});
        }};
/* End PBXProject section */

/* Begin PBXResourcesBuildPhase section */
        {resources_phase} = {{isa = PBXResourcesBuildPhase; buildActionMask = 2147483647; files = ({asset_build}); runOnlyForDeploymentPostprocessing = 0; }};
/* End PBXResourcesBuildPhase section */

/* Begin PBXSourcesBuildPhase section */
        {sources_phase} = {{
            isa = PBXSourcesBuildPhase;
            buildActionMask = 2147483647;
            files = (
{chr(10).join(source_members)}
            );
            runOnlyForDeploymentPostprocessing = 0;
        }};
/* End PBXSourcesBuildPhase section */

/* Begin XCBuildConfiguration section */
{chr(10).join(configs)}
/* End XCBuildConfiguration section */

/* Begin XCConfigurationList section */
        {project_configs} = {{isa = XCConfigurationList; buildConfigurations = ({identifier('project:Debug')}, {identifier('project:Release')}); defaultConfigurationIsVisible = 0; defaultConfigurationName = Release; }};
        {target_configs} = {{isa = XCConfigurationList; buildConfigurations = ({identifier('target:Debug')}, {identifier('target:Release')}); defaultConfigurationIsVisible = 0; defaultConfigurationName = Release; }};
/* End XCConfigurationList section */
    }};
    rootObject = {project_id};
}}
'''
    PROJECT.mkdir(parents=True, exist_ok=True)
    (PROJECT / "project.pbxproj").write_text(output)

    scheme_directory = PROJECT / "xcshareddata" / "xcschemes"
    scheme_directory.mkdir(parents=True, exist_ok=True)
    buildable = (
        f'<BuildableReference BuildableIdentifier="primary" BlueprintIdentifier="{target_id}" '
        'BuildableName="FolioVoice.app" BlueprintName="FolioVoice" '
        'ReferencedContainer="container:FolioVoice.xcodeproj"/>'
    )
    scheme = f'''<?xml version="1.0" encoding="UTF-8"?>
<Scheme LastUpgradeVersion="1600" version="1.3">
  <BuildAction parallelizeBuildables="YES" buildImplicitDependencies="YES">
    <BuildActionEntries>
      <BuildActionEntry buildForTesting="YES" buildForRunning="YES" buildForProfiling="YES" buildForArchiving="YES" buildForAnalyzing="YES">
        {buildable}
      </BuildActionEntry>
    </BuildActionEntries>
  </BuildAction>
  <TestAction buildConfiguration="Debug" selectedDebuggerIdentifier="Xcode.DebuggerFoundation.Debugger.LLDB" selectedLauncherIdentifier="Xcode.IDEFoundation.Launcher.LLDB" shouldUseLaunchSchemeArgsEnv="YES"><Testables/></TestAction>
  <LaunchAction buildConfiguration="Debug" selectedDebuggerIdentifier="Xcode.DebuggerFoundation.Debugger.LLDB" selectedLauncherIdentifier="Xcode.IDEFoundation.Launcher.LLDB" launchStyle="0" useCustomWorkingDirectory="NO" ignoresPersistentStateOnLaunch="NO" debugDocumentVersioning="YES" debugServiceExtension="internal" allowLocationSimulation="YES">
    <BuildableProductRunnable runnableDebuggingMode="0">{buildable}</BuildableProductRunnable>
  </LaunchAction>
  <ProfileAction buildConfiguration="Release" shouldUseLaunchSchemeArgsEnv="YES" savedToolIdentifier="" useCustomWorkingDirectory="NO" debugDocumentVersioning="YES">
    <BuildableProductRunnable runnableDebuggingMode="0">{buildable}</BuildableProductRunnable>
  </ProfileAction>
  <AnalyzeAction buildConfiguration="Debug"/>
  <ArchiveAction buildConfiguration="Release" revealArchiveInOrganizer="YES"/>
</Scheme>
'''
    (scheme_directory / "FolioVoice.xcscheme").write_text(scheme)
    print(f"Generated {PROJECT.name} with {len(sources)} Swift source files.")


if __name__ == "__main__":
    main()
