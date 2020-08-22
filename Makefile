AUTHOR := Klassen Software Solutions
AUTHOR_URL := https://www.kss.cc/

include BuildSystem/swift/common.mk

check: Tests/LinuxMain.swift

TEST_SOURCES := $(wildcard Tests/KSS*Tests/*.swift)

Tests/LinuxMain.swift: $(TEST_SOURCES)
	swift test --generate-linuxmain
