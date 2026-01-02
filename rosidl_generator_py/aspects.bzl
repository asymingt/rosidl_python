# Copyright 2025 Open Source Robotics Foundation, Inc.
#
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.
# You may obtain a copy of the License at
#
#     http://www.apache.org/licenses/LICENSE-2.0
#
# Unless required by applicable law or agreed to in writing, software
# distributed under the License is distributed on an "AS IS" BASIS,
# WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
# See the License for the specific language governing permissions and
# limitations under the License.

load("@bazel_skylib//lib:paths.bzl", "paths")
load("@rosidl_adapter//:tools.bzl", "generate_compilation_information", "generate_sources")
load("@rosidl_adapter//:types.bzl", "RosIdlInfo")
load("@rosidl_cmake//:types.bzl", "RosInterfaceInfo")
load("@rosidl_generator_type_description//:types.bzl", "RosTypeDescriptionInfo")
load("@rosidl_typesupport_c//:types.bzl", "RosCTypesupportInfo")
load("@rules_python//python:defs.bzl", "PyInfo")
load(":types.bzl", "RosPyBindingsInfo")

def _rosidl_generator_py_aspect_impl(target, ctx):

    # Generate source files
    py_files, srcs, _ = generate_sources(
        target = target,
        ctx = ctx,
        executable = ctx.executable._py_generator,
        mnemonic = "PyGeneration",
        input_idls = [target[RosIdlInfo].idl],
        input_type_descriptions = target[RosTypeDescriptionInfo].jsons.to_list(),
        input_templates = ctx.attr._py_templates[DefaultInfo].files.to_list(),
        templates_hdrs = ["_{}.py", "_{}.__init__.py"],
        templates_srcs = ["_{}_s.c", "_{}_s.ep.rosidl_typesupport_c.c"],
        additional = ["--typesupport-impls=rosidl_typesupport_c"],
    )

    # Unpack the generated python files - there are two files per message. One is the
    # python interface, the other is the module initialization file (__init__.py).
    py_interface_file, py_init_file = py_files[0], py_files[1]

    # Collect the set of deps needed to build the C type support module.
    deps = [dep[CcInfo] for dep in ctx.attr._cc_deps if CcInfo in dep]
    deps.append(target[RosCTypesupportInfo].cc_info)
    for dep in ctx.rule.attr.deps:
        if RosPyBindingsInfo in dep:
            deps.extend(dep[RosPyBindingsInfo].cc_infos.to_list())

    # Assemble the CcInfo provider.
    cc_info, dynamic_library = generate_compilation_information(
        ctx = ctx,
        name = "{}__{}__{}__rosidl_generator_py".format(
            target[RosIdlInfo].package_name,
            target[RosIdlInfo].interface_type,
            target[RosIdlInfo].interface_code,
        ),        
        hdrs = [],
        srcs = srcs,
        deps = deps,
        include_dirs = [],
    )

    # At runtime the library path will be mangled like the following:
    #      _solib_k8/_Uexternal_Sfoo+_Smsg/libfoo__msg__bar_s.so
    # We must save this path so that we know where to look at runtime for the shared library.
    py_rlocation_file = ctx.actions.declare_file(
        "{}/{}/_{}__rlocation.py".format(
            target[RosIdlInfo].package_name,
            target[RosIdlInfo].interface_type,
            target[RosIdlInfo].interface_code,
        ),
    )
    ctx.actions.write(
        output = py_rlocation_file,
        content = "TYPESUPPORT_C = '%s'" % dynamic_library.short_path,
    )

    # We need the import path relative to the runfiles root.
    import_path = paths.join(
        target.label.workspace_root.removeprefix("external/"),
        target.label.package,
    )

    # Return the depset of python interfaces and extension modules. These will be
    # aggregated by the rule and placed in the runfile path as needed.
    return [
        RosPyBindingsInfo(
            cc_infos = depset(
                direct = [cc_info],
                transitive = [
                    dep[RosPyBindingsInfo].cc_infos
                    for dep in ctx.rule.attr.deps
                    if RosPyBindingsInfo in dep
                ],
            ),
            transitive_sources = depset(
                direct = [py_interface_file, py_rlocation_file],
                transitive = [
                    dep[RosPyBindingsInfo].transitive_sources
                    for dep in ctx.rule.attr.deps
                    if RosPyBindingsInfo in dep
                ] + [
                    dep[PyInfo].transitive_sources
                    for dep in ctx.attr._py_deps
                    if PyInfo in dep
                ],
            ),
            imports = depset(
                direct = [import_path],
                transitive = [
                    dep[RosPyBindingsInfo].imports
                    for dep in ctx.rule.attr.deps
                    if RosPyBindingsInfo in dep
                ] + [
                    dep[PyInfo].imports
                    for dep in ctx.attr._py_deps
                    if PyInfo in dep
                ],
            ),
            dynamic_libraries = depset(
                direct = [dynamic_library],
                transitive = [
                    dep[RosPyBindingsInfo].dynamic_libraries
                    for dep in ctx.rule.attr.deps
                    if RosPyBindingsInfo in dep
                ],
            ),
        ),
    ]

rosidl_generator_py_aspect = aspect(
    implementation = _rosidl_generator_py_aspect_impl,
    toolchains = ["@rules_cc//cc:toolchain_type"],
    attr_aspects = ["deps"],
    fragments = ["cpp"],
    attrs = {
        #########################################################################
        # Code generation #######################################################
        #########################################################################
        "_py_generator": attr.label(
            default = Label("//:cli"),
            executable = True,
            cfg = "exec",
        ),
        "_py_templates": attr.label(
            default = Label("//:interface_templates"),
        ),

        #########################################################################
        # Dependencies ##########################################################
        #########################################################################
        "_cc_deps": attr.label_list(
            default = [
                Label("@rosdistro//bazel/python/cc:numpy_headers"),
                Label("@rosidl_runtime_c"),
            ],
            providers = [CcInfo],
        ),
        "_py_deps": attr.label_list(
            default = [
                Label("@rosidl_generator_py//:hook"),
            ],
            providers = [PyInfo],
        ),
    },
    required_providers = [RosInterfaceInfo],
    required_aspect_providers = [
        [RosIdlInfo],
        [RosTypeDescriptionInfo],
        [RosCTypesupportInfo],
    ],
    provides = [RosPyBindingsInfo],
)
