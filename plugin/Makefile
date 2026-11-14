# madar-csd — build against the installed Hyprland headers (package: hyprland-dev)
ifeq ($(CXX),g++)
    EXTRA_FLAGS = --no-gnu-unique
else
    EXTRA_FLAGS =
endif

CXXFLAGS = -shared -fPIC -O2 -std=c++2b -Wno-c++11-narrowing
INCLUDES = `pkg-config --cflags pixman-1 libdrm hyprland pangocairo libinput libudev wayland-server xkbcommon`

TARGET = madar-csd.so

all: $(TARGET)

$(TARGET): main.cpp
	$(CXX) $(CXXFLAGS) $(EXTRA_FLAGS) $(INCLUDES) $< -o $@

clean:
	rm -f $(TARGET)

.PHONY: all clean
