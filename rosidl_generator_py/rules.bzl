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

load("@rosidl_adapter//:aspects.bzl", "idl_aspect")
load("@rosidl_cmake//:types.bzl", "RosInterfaceInfo")
load("@rosidl_generator_c//:aspects.bzl", "c_aspect", "c_files_aspect")
load("@rosidl_generator_cpp//:aspects.bzl", "cc_aspect", "cc_files_aspect")
load("@rosidl_typesupport_c//:aspects.bzl", "c_typesupport_aspect", "c_typesupport_files_aspect")
load("@rosidl_generator_type_description//:aspects.bzl", "type_description_aspect")
load("@rules_python//python:defs.bzl", "PyInfo", "py_library")
load(":aspects.bzl", "py_aspect")
load(":types.bzl", "RosPyBindingsInfo")

def _py_ros_library_impl(ctx):
    return [
        DefaultInfo(
            runfiles = ctx.runfiles(
                transitive_files = depset(
                    transitive = [
                        dep[RosPyBindingsInfo].dynamic_libraries
                        for dep in ctx.attr.deps
                        if RosPyBindingsInfo in dep
                    ],
                ),
            ),
        ),
        PyInfo(
            imports = depset(
                transitive = [
                    dep[RosPyBindingsInfo].imports
                    for dep in ctx.attr.deps
                    if RosPyBindingsInfo in dep
                ],
            ),
            transitive_sources = depset(
                transitive = [
                    dep[RosPyBindingsInfo].transitive_sources
                    for dep in ctx.attr.deps
                    if RosPyBindingsInfo in dep
                ],
            ),
        ),
    ]

py_ros_library_rule = rule(
    implementation = _py_ros_library_impl,
    attrs = {
        "deps": attr.label_list(
            aspects = [
                idl_aspect,  # RosIdlInfo
                type_description_aspect,  # RosTypeDescriptionInfo
                c_files_aspect,  # RosCBindingsFilesInfo
                c_aspect,  # RosCBindingsInfo
                cc_files_aspect, # RosCcBindingsFilesInfo
                cc_aspect, # RosCcBindingsInfo
                c_typesupport_files_aspect, # RosCTypesupportFilesInfo
                c_typesupport_aspect, # RosCTypesupportInfo
                py_aspect,  # RosCcBindingsInfo
            ],
            providers = [RosInterfaceInfo],
            allow_files = False,
        ),
    },
    provides = [DefaultInfo, PyInfo],
)

def py_ros_library(name, deps):
    rule_name = "{}_internal".format(name)
    py_ros_library_rule(
        name = rule_name,
        deps = deps,
    )
    py_library(
        name = name,
        deps = [
            ":{}".format(rule_name),
            "@rosidl_generator_py",
        ],
    )
