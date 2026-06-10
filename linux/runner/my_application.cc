#include "my_application.h"

#include <flutter_linux/flutter_linux.h>
#ifdef GDK_WINDOWING_X11
#include <gdk/gdkx.h>
#endif

#include <libnotify/notify.h>
#include <gtk/gtk.h>

#include "flutter/generated_plugin_registrant.h"

struct _MyApplication {
  GtkApplication parent_instance;
  char** dart_entrypoint_arguments;
};

G_DEFINE_TYPE(MyApplication, my_application, GTK_TYPE_APPLICATION)

static GtkWindow* g_main_window = nullptr;
static FlMethodChannel* g_window_channel = nullptr;

// Called when first Flutter frame received.
static void first_frame_cb(MyApplication* self, FlView* view) {
  gtk_widget_show(gtk_widget_get_toplevel(GTK_WIDGET(view)));
}

// Method call handler for window actions on Linux.
static void window_method_call(FlMethodChannel* channel,
                               FlMethodCall* method_call,
                               gpointer user_data) {
  const gchar* method = fl_method_call_get_name(method_call);
  FlValue* args = fl_method_call_get_args(method_call);
  g_autoptr(FlMethodResponse) response = nullptr;

  if (g_str_equal(method, "flashTaskbar")) {
    if (g_main_window) {
      // Request attention from the WM (urgency hint)
      gtk_window_set_urgency_hint(g_main_window, TRUE);
      response = FL_METHOD_RESPONSE(fl_method_success_response_new(fl_value_new_bool(TRUE)));
    } else {
      response = FL_METHOD_RESPONSE(fl_method_success_response_new(fl_value_new_bool(FALSE)));
    }
    fl_method_call_respond(method_call, response, nullptr);
    return;
  }

  if (g_str_equal(method, "notify")) {
    const char* title = "SimplePresent";
    const char* body = "";
    const char* requested_icon = NULL;
    if (args && fl_value_get_type(args) == FL_VALUE_TYPE_MAP) {
      FlValue* v = fl_value_lookup_string(args, "title");
      if (v && fl_value_get_type(v) == FL_VALUE_TYPE_STRING) title = fl_value_get_string(v);
      v = fl_value_lookup_string(args, "body");
      if (v && fl_value_get_type(v) == FL_VALUE_TYPE_STRING) body = fl_value_get_string(v);
      v = fl_value_lookup_string(args, "icon");
      if (v && fl_value_get_type(v) == FL_VALUE_TYPE_STRING) requested_icon = fl_value_get_string(v);
    }
    // If no title provided, try to use current window title
    if ((title == NULL || title[0] == '\0') && g_main_window) {
      const gchar* wt = gtk_window_get_title(g_main_window);
      if (wt && wt[0] != '\0') title = wt;
    }
    if (!notify_is_initted()) notify_init("SimplePresent");
    // Determine icon: prefer explicit 'icon' arg, otherwise search common asset locations
    const char* chosen_icon = NULL;
    if (requested_icon && requested_icon[0] != '\0') {
      // If the caller provided a path, check it directly and also try prefixed asset locations
      if (g_file_test(requested_icon, G_FILE_TEST_EXISTS)) {
        chosen_icon = requested_icon;
      } else {
        // Try common prefixes (data/flutter_assets, ../data/flutter_assets, flutter_assets)
        char buf[1024];
        snprintf(buf, sizeof(buf), "data/flutter_assets/%s", requested_icon);
        if (g_file_test(buf, G_FILE_TEST_EXISTS)) chosen_icon = g_strdup(buf);
        else {
          snprintf(buf, sizeof(buf), "../data/flutter_assets/%s", requested_icon);
          if (g_file_test(buf, G_FILE_TEST_EXISTS)) chosen_icon = g_strdup(buf);
          else {
            snprintf(buf, sizeof(buf), "flutter_assets/%s", requested_icon);
            if (g_file_test(buf, G_FILE_TEST_EXISTS)) chosen_icon = g_strdup(buf);
          }
        }
      }
    }
    if (!chosen_icon) {
      // Fallback: try to find a bundled icon from common asset locations
      const char* icon_candidates[] = {
        "data/flutter_assets/assets/icons/icon.png",
        "../data/flutter_assets/assets/icons/icon.png",
        "flutter_assets/assets/icons/icon.png",
        "data/flutter_assets/assets/icons/icon.svg",
        "../data/flutter_assets/assets/icons/icon.svg",
        "flutter_assets/assets/icons/icon.svg",
        NULL
      };
      for (int i = 0; icon_candidates[i] != NULL; ++i) {
        if (g_file_test(icon_candidates[i], G_FILE_TEST_EXISTS)) {
          chosen_icon = icon_candidates[i];
          break;
        }
      }
    }
    NotifyNotification* n = notify_notification_new(title, body, chosen_icon);
    GError* err = nullptr;
    notify_notification_show(n, &err);
    if (err) {
      g_warning("notify error: %s", err->message);
      g_clear_error(&err);
      response = FL_METHOD_RESPONSE(fl_method_success_response_new(fl_value_new_bool(FALSE)));
    } else {
      response = FL_METHOD_RESPONSE(fl_method_success_response_new(fl_value_new_bool(TRUE)));
    }
    fl_method_call_respond(method_call, response, nullptr);
    return;
  }

  if (g_str_equal(method, "bringToFront")) {
    if (g_main_window) {
      // Present brings to front and gives focus
      gtk_window_present(g_main_window);
      response = FL_METHOD_RESPONSE(fl_method_success_response_new(fl_value_new_bool(TRUE)));
    } else {
      response = FL_METHOD_RESPONSE(fl_method_success_response_new(fl_value_new_bool(FALSE)));
    }
    fl_method_call_respond(method_call, response, nullptr);
    return;
  }

  if (g_str_equal(method, "setWindowGeometry")) {
    if (g_main_window && args && fl_value_get_type(args) == FL_VALUE_TYPE_MAP) {
      // Support always_on_top and maximized flags even if geometry not provided
      FlValue* val_always = fl_value_lookup_string(args, "always_on_top");
      if (val_always && fl_value_get_type(val_always) == FL_VALUE_TYPE_BOOL) {
        gtk_window_set_keep_above(g_main_window, fl_value_get_bool(val_always));
        response = FL_METHOD_RESPONSE(fl_method_success_response_new(fl_value_new_bool(TRUE)));
        fl_method_call_respond(method_call, response, nullptr);
        return;
      }
      FlValue* vmax = fl_value_lookup_string(args, "maximized");
      if (vmax && fl_value_get_type(vmax) == FL_VALUE_TYPE_BOOL && fl_value_get_bool(vmax)) {
        gtk_window_maximize(g_main_window);
        response = FL_METHOD_RESPONSE(fl_method_success_response_new(fl_value_new_bool(TRUE)));
        fl_method_call_respond(method_call, response, nullptr);
        return;
      }
      FlValue* vx = fl_value_lookup_string(args, "x");
      FlValue* vy = fl_value_lookup_string(args, "y");
      FlValue* vw = fl_value_lookup_string(args, "width");
      FlValue* vh = fl_value_lookup_string(args, "height");
      if (vx && vy && vw && vh && fl_value_get_type(vx) == FL_VALUE_TYPE_INT && fl_value_get_type(vy) == FL_VALUE_TYPE_INT && fl_value_get_type(vw) == FL_VALUE_TYPE_INT && fl_value_get_type(vh) == FL_VALUE_TYPE_INT) {
        const int x = fl_value_get_int(vx);
        const int y = fl_value_get_int(vy);
        const int w = fl_value_get_int(vw);
        const int h = fl_value_get_int(vh);
        // Ensure we unmaximize before setting geometry
        gtk_window_unmaximize(g_main_window);
        gtk_window_move(g_main_window, x, y);
        gtk_window_resize(g_main_window, w, h);
        response = FL_METHOD_RESPONSE(fl_method_success_response_new(fl_value_new_bool(TRUE)));
        fl_method_call_respond(method_call, response, nullptr);
        return;
      }
    }
    response = FL_METHOD_RESPONSE(fl_method_success_response_new(fl_value_new_bool(FALSE)));
    fl_method_call_respond(method_call, response, nullptr);
    return;
  }

  if (g_str_equal(method, "getWindowGeometry")) {
    if (g_main_window) {
      int x, y, w, h;
      gtk_window_get_position(g_main_window, &x, &y);
      gtk_window_get_size(g_main_window, &w, &h);
      FlValue* map = fl_value_new_map();
      fl_value_set_string_take(map, "x", fl_value_new_int(x));
      fl_value_set_string_take(map, "y", fl_value_new_int(y));
      fl_value_set_string_take(map, "width", fl_value_new_int(w));
      fl_value_set_string_take(map, "height", fl_value_new_int(h));
      // Report maximized state
      gboolean is_max = gtk_window_is_maximized(g_main_window);
      fl_value_set_string_take(map, "maximized", fl_value_new_bool(is_max));
      response = FL_METHOD_RESPONSE(fl_method_success_response_new(map));
      fl_method_call_respond(method_call, response, nullptr);
      return;
    }
    response = FL_METHOD_RESPONSE(fl_method_success_response_new(fl_value_new_map()));
    fl_method_call_respond(method_call, response, nullptr);
    return;
  }

  if (g_str_equal(method, "getScreenSize")) {
    // Return primary monitor size as map {width, height}
    GdkDisplay* display = gdk_display_get_default();
    if (display) {
      GdkMonitor* mon = gdk_display_get_primary_monitor(display);
      int sw = 0, sh = 0;
      if (mon) {
        GdkRectangle rect;
        gdk_monitor_get_geometry(mon, &rect);
        sw = rect.width;
        sh = rect.height;
      } else {
        // Fallback: try to get monitor 0 geometry (avoids deprecated gdk_screen_* APIs)
        int n = gdk_display_get_n_monitors(display);
        if (n > 0) {
          GdkMonitor* m0 = gdk_display_get_monitor(display, 0);
          if (m0) {
            GdkRectangle rect0;
            gdk_monitor_get_geometry(m0, &rect0);
            sw = rect0.width;
            sh = rect0.height;
          }
        }
      }
      FlValue* map = fl_value_new_map();
      fl_value_set_string_take(map, "width", fl_value_new_int(sw));
      fl_value_set_string_take(map, "height", fl_value_new_int(sh));
      response = FL_METHOD_RESPONSE(fl_method_success_response_new(map));
      fl_method_call_respond(method_call, response, nullptr);
      return;
    }
    response = FL_METHOD_RESPONSE(fl_method_success_response_new(fl_value_new_map()));
    fl_method_call_respond(method_call, response, nullptr);
    return;
  }

  response = FL_METHOD_RESPONSE(fl_method_not_implemented_response_new());
  fl_method_call_respond(method_call, response, nullptr);
}

// Implements GApplication::activate.
static void my_application_activate(GApplication* application) {
  MyApplication* self = MY_APPLICATION(application);
  GtkWindow* window = GTK_WINDOW(gtk_application_window_new(GTK_APPLICATION(application)));

  // Use a header bar when running in GNOME as this is the common style used
  // by applications and is the setup most users will be using (e.g. Ubuntu
  // desktop).
  // If running on X and not using GNOME then just use a traditional title bar
  // in case the window manager does more exotic layout, e.g. tiling.
  // If running on Wayland assume the header bar will work (may need changing
  // if future cases occur).
  gboolean use_header_bar = TRUE;
#ifdef GDK_WINDOWING_X11
  GdkScreen* screen = gtk_window_get_screen(window);
  if (GDK_IS_X11_SCREEN(screen)) {
    const gchar* wm_name = gdk_x11_screen_get_window_manager_name(screen);
    if (g_strcmp0(wm_name, "GNOME Shell") != 0) {
      use_header_bar = FALSE;
    }
  }
#endif
  if (use_header_bar) {
    GtkHeaderBar* header_bar = GTK_HEADER_BAR(gtk_header_bar_new());
    gtk_widget_show(GTK_WIDGET(header_bar));
    gtk_header_bar_set_title(header_bar, "SimplePresent - today");
    gtk_header_bar_set_show_close_button(header_bar, TRUE);
    gtk_window_set_titlebar(window, GTK_WIDGET(header_bar));
  } else {
    gtk_window_set_title(window, "SimplePresent - today");
  }

  gtk_window_set_default_size(window, 600, 900);

  // Attempt to set a custom application icon (used by taskbar/launcher).
  // Check several likely locations where the build/install process may place
  // the Flutter assets so the icon file can be found both in development and
  // in the installed bundle.
  const char* icon_candidates[] = {
    // SVG (original)
    "data/flutter_assets/assets/icons/icon.svg",
    "../data/flutter_assets/assets/icons/icon.svg",
    "flutter_assets/assets/icons/icon.svg",
    // PNG fallback (added by user)
    "data/flutter_assets/assets/icons/icon.png",
    "../data/flutter_assets/assets/icons/icon.png",
    "flutter_assets/assets/icons/icon.png",
    // ICO fallback
    "data/flutter_assets/assets/icons/icon.ico",
    "../data/flutter_assets/assets/icons/icon.ico",
    "flutter_assets/assets/icons/icon.ico",
    // System install location
    "/usr/share/icons/hicolor/scalable/apps/simple_present.svg",
    NULL
  };
  for (int i = 0; icon_candidates[i] != NULL; ++i) {
    const char* path = icon_candidates[i];
    if (g_file_test(path, G_FILE_TEST_EXISTS)) {
      g_autoptr(GError) err = NULL;
      if (gtk_window_set_default_icon_from_file(path, &err)) {
        g_message("Set application icon from %s", path);
      } else {
        g_warning("Failed to set icon from %s: %s", path, err ? err->message : "unknown");
      }
      break;
    }
  }

  g_autoptr(FlDartProject) project = fl_dart_project_new();
  fl_dart_project_set_dart_entrypoint_arguments(project, self->dart_entrypoint_arguments);

  FlView* view = fl_view_new(project);
  GdkRGBA background_color;
  // Background defaults to black, override it here if necessary, e.g. #00000000
  // for transparent.
  gdk_rgba_parse(&background_color, "#000000");
  fl_view_set_background_color(view, &background_color);
  gtk_widget_show(GTK_WIDGET(view));
  gtk_container_add(GTK_CONTAINER(window), GTK_WIDGET(view));

  // Show the window when Flutter renders.
  // Requires the view to be realized so we can start rendering.
  g_signal_connect_swapped(view, "first-frame", G_CALLBACK(first_frame_cb), self);
  gtk_widget_realize(GTK_WIDGET(view));

  // Store global pointer for method handlers
  g_main_window = window;

  // Register a method channel for window operations
  FlEngine* engine = fl_view_get_engine(view);
  FlBinaryMessenger* messenger = fl_engine_get_binary_messenger(engine);
  g_autoptr(FlStandardMethodCodec) codec = fl_standard_method_codec_new();
  g_window_channel = fl_method_channel_new(messenger, "simple_present/window", FL_METHOD_CODEC(codec));
  fl_method_channel_set_method_call_handler(g_window_channel, window_method_call, nullptr, nullptr);

  fl_register_plugins(FL_PLUGIN_REGISTRY(view));

  gtk_widget_grab_focus(GTK_WIDGET(view));
}

// Implements GApplication::local_command_line.
static gboolean my_application_local_command_line(GApplication* application,
                                                  gchar*** arguments,
                                                  int* exit_status) {
  MyApplication* self = MY_APPLICATION(application);
  // Strip out the first argument as it is the binary name.
  self->dart_entrypoint_arguments = g_strdupv(*arguments + 1);

  g_autoptr(GError) error = nullptr;
  if (!g_application_register(application, nullptr, &error)) {
    g_warning("Failed to register: %s", error->message);
    *exit_status = 1;
    return TRUE;
  }

  g_application_activate(application);
  *exit_status = 0;

  return TRUE;
}

// Implements GApplication::startup.
static void my_application_startup(GApplication* application) {
  // MyApplication* self = MY_APPLICATION(object);

  // Perform any actions required at application startup.

  G_APPLICATION_CLASS(my_application_parent_class)->startup(application);
}

// Implements GApplication::shutdown.
static void my_application_shutdown(GApplication* application) {
  // MyApplication* self = MY_APPLICATION(object);

  // Perform any actions required at application shutdown.

  G_APPLICATION_CLASS(my_application_parent_class)->shutdown(application);
}

// Implements GObject::dispose.
static void my_application_dispose(GObject* object) {
  MyApplication* self = MY_APPLICATION(object);
  g_clear_pointer(&self->dart_entrypoint_arguments, g_strfreev);
  G_OBJECT_CLASS(my_application_parent_class)->dispose(object);
}

static void my_application_class_init(MyApplicationClass* klass) {
  G_APPLICATION_CLASS(klass)->activate = my_application_activate;
  G_APPLICATION_CLASS(klass)->local_command_line = my_application_local_command_line;
  G_APPLICATION_CLASS(klass)->startup = my_application_startup;
  G_APPLICATION_CLASS(klass)->shutdown = my_application_shutdown;
  G_OBJECT_CLASS(klass)->dispose = my_application_dispose;
}

static void my_application_init(MyApplication* self) {}

MyApplication* my_application_new() {
  // Set the program name to the application ID, which helps various systems
  // like GTK and desktop environments map this running application to its
  // corresponding .desktop file. This ensures better integration by allowing
  // the application to be recognized beyond its binary name.
  g_set_prgname(APPLICATION_ID);

  return MY_APPLICATION(g_object_new(my_application_get_type(),
                                     "application-id", APPLICATION_ID, "flags",
                                     G_APPLICATION_NON_UNIQUE, nullptr));
}
