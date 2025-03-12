project('curl', 'vala', 'c')
project_name = 'io.github.trbjo.bob.libraries.curl'

vapi_dir = join_paths(meson.current_source_dir(), 'vapi')
inc = include_directories('src')


proj_deps = {
    'posix': meson.get_compiler('vala').find_library('posix'),
    'glib': dependency('glib-2.0'),
    'gio': dependency('gio-2.0'),
    'libcurl': dependency('libcurl', version: '>=8.10.1'),
}

deps_list = []
foreach dep_name, dep : proj_deps
    deps_list += dep
endforeach

sources = files(
    'src/curl.vala',
)

# message('Current source dir: ' + meson.current_source_dir())
curl_lib = static_library('curl',
    sources,
    dependencies: deps_list,
    vala_args: [
        '--vapidir', join_paths(meson.current_source_dir(), 'vapi'),
        '--pkg', 'libcurl',
    ],
    install: true,
)

curl_dep = declare_dependency(
    link_with: curl_lib,
    dependencies: deps_list,
    include_directories: include_directories('.'),
    variables: {'vapi_dir': vapi_dir}
)
