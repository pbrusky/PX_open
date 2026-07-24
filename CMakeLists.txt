cmake_minimum_required(VERSION 3.16)

project(PX_open LANGUAGES CXX)

#
# Add the client (Qt/C++) project
#
add_subdirectory("PX Open Client")

#
# Install / package the Python server module
#
install(
    DIRECTORY "Server Module/"
    DESTINATION server_module
    FILES_MATCHING PATTERN "*.py"
)

#
# Optional: include non-Python files (config, assets)
#
install(
    DIRECTORY "Server Module/"
    DESTINATION server_module
    PATTERN "*.py" EXCLUDE
)
