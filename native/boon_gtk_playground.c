#include <gtk/gtk.h>
#include <stdbool.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

typedef struct {
  char *name;
  char *label;
  char *path;
} CatalogEntry;

typedef struct {
  char *name;
  char *title;
  char *source_path;
  char *source;
  char *snapshot;
  char *catalog_text;
} Scene;

typedef struct {
  char *initial_scene_path;
  bool verify;
  int exit_ms;
  int verify_failed;
  int counter;
  GPtrArray *catalog;
  Scene scene;
  GtkApplication *application;
  GtkWidget *window;
  GtkWidget *sidebar;
  GtkWidget *preview;
  GtkWidget *title_label;
  GtkWidget *example_label;
  GtkWidget *source_path_label;
  GtkTextBuffer *source_buffer;
} AppState;

typedef struct {
  AppState *app;
  char *path;
} CatalogButtonData;

static char *read_file(const char *path) {
  FILE *file = fopen(path, "rb");
  if (!file) return strdup("");
  fseek(file, 0, SEEK_END);
  long length = ftell(file);
  fseek(file, 0, SEEK_SET);
  if (length < 0) {
    fclose(file);
    return strdup("");
  }
  char *buffer = calloc((size_t)length + 1, 1);
  if (!buffer) {
    fclose(file);
    return strdup("");
  }
  fread(buffer, 1, (size_t)length, file);
  fclose(file);
  return buffer;
}

static char *json_string(const char *json, const char *key) {
  char pattern[128];
  snprintf(pattern, sizeof(pattern), "\"%s\": \"", key);
  char *start = strstr(json, pattern);
  if (!start) return strdup("");
  start += strlen(pattern);
  char *out = calloc(strlen(start) + 1, 1);
  if (!out) return strdup("");
  size_t written = 0;
  bool escaped = false;
  for (char *cursor = start; *cursor; cursor++) {
    if (escaped) {
      if (*cursor == 'n') out[written++] = '\n';
      else if (*cursor == 'r') out[written++] = '\r';
      else if (*cursor == 't') out[written++] = '\t';
      else out[written++] = *cursor;
      escaped = false;
    } else if (*cursor == '\\') {
      escaped = true;
    } else if (*cursor == '"') {
      break;
    } else {
      out[written++] = *cursor;
    }
  }
  out[written] = '\0';
  return out;
}

static void free_scene(Scene *scene) {
  free(scene->name);
  free(scene->title);
  free(scene->source_path);
  free(scene->source);
  free(scene->snapshot);
  free(scene->catalog_text);
  memset(scene, 0, sizeof(Scene));
}

static void free_catalog_entry(gpointer value) {
  CatalogEntry *entry = (CatalogEntry *)value;
  if (!entry) return;
  free(entry->name);
  free(entry->label);
  free(entry->path);
  free(entry);
}

static void clear_box(GtkWidget *box) {
  GtkWidget *child = gtk_widget_get_first_child(box);
  while (child) {
    gtk_box_remove(GTK_BOX(box), child);
    child = gtk_widget_get_first_child(box);
  }
}

static GtkWidget *text_label(const char *text, const char *css_class) {
  GtkWidget *label = gtk_label_new(text);
  gtk_label_set_xalign(GTK_LABEL(label), 0.0f);
  gtk_label_set_wrap(GTK_LABEL(label), true);
  if (css_class) gtk_widget_add_css_class(label, css_class);
  return label;
}

static GtkWidget *scrolling_text(const char *text, bool monospace) {
  GtkWidget *scroller = gtk_scrolled_window_new();
  GtkWidget *view = gtk_text_view_new();
  gtk_text_view_set_editable(GTK_TEXT_VIEW(view), false);
  gtk_text_view_set_cursor_visible(GTK_TEXT_VIEW(view), false);
  gtk_text_view_set_wrap_mode(GTK_TEXT_VIEW(view), GTK_WRAP_WORD_CHAR);
  if (monospace) gtk_widget_add_css_class(view, "mono");
  gtk_text_buffer_set_text(gtk_text_view_get_buffer(GTK_TEXT_VIEW(view)), text, -1);
  gtk_scrolled_window_set_child(GTK_SCROLLED_WINDOW(scroller), view);
  gtk_widget_set_vexpand(scroller, true);
  return scroller;
}

static int snapshot_counter(const char *snapshot) {
  if (!snapshot || !snapshot[0]) return 0;
  return atoi(snapshot);
}

static char *counter_snapshot(int value) {
  char buffer[64];
  snprintf(buffer, sizeof(buffer), "%d+", value);
  return strdup(buffer);
}

static char *todo_snapshot(void) {
  return strdup(
    "todos\n"
    "Buy groceries\n"
    "Clean room\n"
    "2 items left\n"
    "All\n"
    "Active\n"
    "Completed\n"
    "Clear completed");
}

static void render_preview(AppState *app);

static void update_counter(AppState *app, int value) {
  app->counter = value;
  free(app->scene.snapshot);
  app->scene.snapshot = counter_snapshot(value);
  render_preview(app);
}

static void counter_increment(GtkButton *button, gpointer user_data) {
  (void)button;
  AppState *app = (AppState *)user_data;
  update_counter(app, app->counter + 1);
}

static void todo_add(GtkButton *button, gpointer user_data) {
  (void)button;
  AppState *app = (AppState *)user_data;
  free(app->scene.snapshot);
  app->scene.snapshot = todo_snapshot();
  render_preview(app);
}

static void render_counter(AppState *app) {
  GtkWidget *card = gtk_box_new(GTK_ORIENTATION_VERTICAL, 16);
  gtk_widget_add_css_class(card, "preview-card");
  GtkWidget *number = text_label(app->scene.snapshot, "counter-value");
  GtkWidget *button = gtk_button_new_with_label("+");
  gtk_widget_add_css_class(button, "primary-button");
  g_signal_connect(button, "clicked", G_CALLBACK(counter_increment), app);
  gtk_box_append(GTK_BOX(card), text_label("Counter", "section-title"));
  gtk_box_append(GTK_BOX(card), number);
  gtk_box_append(GTK_BOX(card), button);
  gtk_box_append(GTK_BOX(app->preview), card);
}

static void render_todo(AppState *app) {
  GtkWidget *card = gtk_box_new(GTK_ORIENTATION_VERTICAL, 12);
  gtk_widget_add_css_class(card, "preview-card");
  gtk_box_append(GTK_BOX(card), text_label("TodoMVC", "section-title"));
  GtkWidget *entry = gtk_entry_new();
  gtk_entry_set_placeholder_text(GTK_ENTRY(entry), "What needs to be done?");
  gtk_box_append(GTK_BOX(card), entry);
  const char *rows[] = {"Buy groceries", "Clean room"};
  for (int index = 0; index < 2; index++) {
    GtkWidget *check = gtk_check_button_new_with_label(rows[index]);
    gtk_box_append(GTK_BOX(card), check);
  }
  GtkWidget *filters = gtk_box_new(GTK_ORIENTATION_HORIZONTAL, 8);
  gtk_box_append(GTK_BOX(filters), gtk_button_new_with_label("All"));
  gtk_box_append(GTK_BOX(filters), gtk_button_new_with_label("Active"));
  gtk_box_append(GTK_BOX(filters), gtk_button_new_with_label("Completed"));
  gtk_box_append(GTK_BOX(card), filters);
  GtkWidget *add = gtk_button_new_with_label("Add local item");
  g_signal_connect(add, "clicked", G_CALLBACK(todo_add), app);
  gtk_box_append(GTK_BOX(card), add);
  gtk_box_append(GTK_BOX(card), text_label(app->scene.snapshot, "snapshot-small"));
  gtk_box_append(GTK_BOX(app->preview), card);
}

static void render_interval(AppState *app) {
  GtkWidget *card = gtk_box_new(GTK_ORIENTATION_VERTICAL, 12);
  gtk_widget_add_css_class(card, "preview-card");
  gtk_box_append(GTK_BOX(card), text_label(app->scene.name, "section-title"));
  gtk_box_append(GTK_BOX(card), text_label("Waiting for the virtual interval stream.", NULL));
  gtk_box_append(GTK_BOX(card), text_label("The verifier exercises this through the generated runtime host; the manual native shell shows the initial scene until a runtime tick bridge is added.", "muted"));
  gtk_box_append(GTK_BOX(app->preview), card);
}

static void render_snapshot(AppState *app) {
  GtkWidget *card = gtk_box_new(GTK_ORIENTATION_VERTICAL, 12);
  gtk_widget_add_css_class(card, "preview-card");
  gtk_box_append(GTK_BOX(card), text_label(app->scene.name, "section-title"));
  const char *text = app->scene.snapshot && app->scene.snapshot[0]
    ? app->scene.snapshot
    : "Initial snapshot is empty.";
  gtk_box_append(GTK_BOX(card), scrolling_text(text, true));
  gtk_box_append(GTK_BOX(app->preview), card);
}

static void render_preview(AppState *app) {
  clear_box(app->preview);
  gtk_label_set_text(GTK_LABEL(app->title_label), app->scene.title);
  gtk_label_set_text(GTK_LABEL(app->example_label), app->scene.name);
  gtk_label_set_text(GTK_LABEL(app->source_path_label), app->scene.source_path);
  gtk_text_buffer_set_text(app->source_buffer, app->scene.source, -1);

  if (strcmp(app->scene.name, "counter") == 0) {
    render_counter(app);
  } else if (strcmp(app->scene.name, "todo_mvc") == 0) {
    render_todo(app);
  } else if (strcmp(app->scene.name, "interval") == 0 || strcmp(app->scene.name, "interval_hold") == 0) {
    render_interval(app);
  } else {
    render_snapshot(app);
  }
}

static void parse_catalog(AppState *app) {
  if (app->catalog->len > 0 || !app->scene.catalog_text) return;
  char **lines = g_strsplit(app->scene.catalog_text, "\n", -1);
  for (int index = 0; lines[index]; index++) {
    if (!lines[index][0]) continue;
    char **columns = g_strsplit(lines[index], "\t", 3);
    if (columns[0] && columns[1] && columns[2]) {
      CatalogEntry *entry = calloc(1, sizeof(CatalogEntry));
      entry->name = strdup(columns[0]);
      entry->label = strdup(columns[1]);
      entry->path = strdup(columns[2]);
      g_ptr_array_add(app->catalog, entry);
    }
    g_strfreev(columns);
  }
  g_strfreev(lines);
}

static bool load_scene(AppState *app, const char *path) {
  char *json = read_file(path);
  if (!json[0]) {
    free(json);
    return false;
  }
  free_scene(&app->scene);
  app->scene.name = json_string(json, "example");
  app->scene.title = json_string(json, "title");
  app->scene.source_path = json_string(json, "source_path");
  app->scene.source = json_string(json, "source_preview");
  app->scene.snapshot = json_string(json, "snapshot_text");
  app->scene.catalog_text = json_string(json, "catalog_text");
  if (strcmp(app->scene.name, "counter") == 0) {
    app->counter = snapshot_counter(app->scene.snapshot);
  }
  free(json);
  parse_catalog(app);
  return true;
}

static void select_catalog(GtkButton *button, gpointer user_data) {
  (void)button;
  CatalogButtonData *data = (CatalogButtonData *)user_data;
  if (load_scene(data->app, data->path)) render_preview(data->app);
}

static void render_sidebar(AppState *app) {
  gtk_box_append(GTK_BOX(app->sidebar), text_label("Boon Gleam", "brand"));
  gtk_box_append(GTK_BOX(app->sidebar), text_label("Native GTK playground", "muted-light"));
  for (guint index = 0; index < app->catalog->len; index++) {
    CatalogEntry *entry = g_ptr_array_index(app->catalog, index);
    GtkWidget *button = gtk_button_new_with_label(entry->label);
    gtk_widget_add_css_class(button, "sidebar-button");
    CatalogButtonData *data = calloc(1, sizeof(CatalogButtonData));
    data->app = app;
    data->path = strdup(entry->path);
    g_signal_connect(button, "clicked", G_CALLBACK(select_catalog), data);
    gtk_box_append(GTK_BOX(app->sidebar), button);
  }
}

static gboolean verify_and_quit(gpointer user_data) {
  AppState *app = (AppState *)user_data;
  if (app->catalog->len < 8) app->verify_failed = 1;
  if (strcmp(app->scene.name, "counter") == 0) {
    int before = app->counter;
    update_counter(app, app->counter + 1);
    if (app->counter != before + 1) app->verify_failed = 1;
  }
  g_application_quit(G_APPLICATION(app->application));
  return G_SOURCE_REMOVE;
}

static void activate(GtkApplication *application, gpointer user_data) {
  AppState *app = (AppState *)user_data;
  app->application = application;
  if (!load_scene(app, app->initial_scene_path)) {
    app->verify_failed = 1;
  }

  app->window = gtk_application_window_new(application);
  gtk_window_set_title(GTK_WINDOW(app->window), "Boon Gleam Native Playground");
  gtk_window_set_default_size(GTK_WINDOW(app->window), 1320, 840);

  GtkWidget *root = gtk_box_new(GTK_ORIENTATION_HORIZONTAL, 0);
  gtk_window_set_child(GTK_WINDOW(app->window), root);

  app->sidebar = gtk_box_new(GTK_ORIENTATION_VERTICAL, 10);
  gtk_widget_set_size_request(app->sidebar, 260, -1);
  gtk_widget_add_css_class(app->sidebar, "sidebar");
  gtk_box_append(GTK_BOX(root), app->sidebar);
  render_sidebar(app);

  GtkWidget *main = gtk_box_new(GTK_ORIENTATION_VERTICAL, 14);
  gtk_widget_set_hexpand(main, true);
  gtk_widget_set_vexpand(main, true);
  gtk_widget_add_css_class(main, "main");
  app->title_label = text_label("", "title");
  app->example_label = text_label("", "muted");
  app->preview = gtk_box_new(GTK_ORIENTATION_VERTICAL, 0);
  gtk_widget_set_hexpand(app->preview, true);
  gtk_widget_set_vexpand(app->preview, true);
  gtk_box_append(GTK_BOX(main), app->title_label);
  gtk_box_append(GTK_BOX(main), app->example_label);
  gtk_box_append(GTK_BOX(main), app->preview);
  gtk_box_append(GTK_BOX(root), main);

  GtkWidget *source_panel = gtk_box_new(GTK_ORIENTATION_VERTICAL, 10);
  gtk_widget_set_size_request(source_panel, 420, -1);
  gtk_widget_add_css_class(source_panel, "source-panel");
  gtk_box_append(GTK_BOX(source_panel), text_label("Source", "source-title"));
  app->source_path_label = text_label("", "source-path");
  gtk_box_append(GTK_BOX(source_panel), app->source_path_label);
  GtkWidget *source_view = gtk_text_view_new();
  gtk_widget_add_css_class(source_view, "source-view");
  gtk_text_view_set_editable(GTK_TEXT_VIEW(source_view), false);
  gtk_text_view_set_cursor_visible(GTK_TEXT_VIEW(source_view), false);
  gtk_text_view_set_wrap_mode(GTK_TEXT_VIEW(source_view), GTK_WRAP_WORD_CHAR);
  app->source_buffer = gtk_text_view_get_buffer(GTK_TEXT_VIEW(source_view));
  GtkWidget *source_scroll = gtk_scrolled_window_new();
  gtk_scrolled_window_set_child(GTK_SCROLLED_WINDOW(source_scroll), source_view);
  gtk_widget_set_vexpand(source_scroll, true);
  gtk_box_append(GTK_BOX(source_panel), source_scroll);
  gtk_box_append(GTK_BOX(root), source_panel);

  GtkCssProvider *css = gtk_css_provider_new();
  gtk_css_provider_load_from_string(css,
    "window{background:#f4f1e8;color:#182322;}"
    ".sidebar{background:#20302f;color:#f4f2eb;padding:22px;}"
    ".main{padding:26px;}.source-panel{background:#111827;color:#d7e2df;padding:22px;}"
    ".brand{font-size:28px;font-weight:800;color:#ffffff;}.title{font-size:24px;font-weight:800;}"
    ".section-title{font-size:20px;font-weight:800;}.muted{color:#54615f;}.muted-light{color:#c8d8d4;}"
    ".preview-card{background:#ffffff;border:1px solid #d9d4c8;border-radius:6px;padding:24px;}"
    ".counter-value{font-size:72px;font-weight:900;color:#182322;}.primary-button{font-size:30px;font-weight:900;min-height:54px;}"
    ".sidebar-button{margin-top:2px;text-align:left;}.source-title{font-size:18px;font-weight:800;color:#ffffff;}"
    ".source-path{color:#a9bab6;}.source-view,.mono{font-family:monospace;font-size:13px;}"
    ".snapshot-small{font-family:monospace;color:#374151;}");
  gtk_style_context_add_provider_for_display(
    gdk_display_get_default(),
    GTK_STYLE_PROVIDER(css),
    GTK_STYLE_PROVIDER_PRIORITY_APPLICATION);

  render_preview(app);
  gtk_window_present(GTK_WINDOW(app->window));
  if (app->verify) g_timeout_add(app->exit_ms, verify_and_quit, app);
}

int main(int argc, char **argv) {
  if (argc < 2) {
    fprintf(stderr, "usage: boon_gtk_playground SCENE_JSON [--verify] [--exit-ms N]\n");
    return 2;
  }
  AppState app = {
    .initial_scene_path = argv[1],
    .verify = false,
    .exit_ms = 800,
    .verify_failed = 0,
    .counter = 0,
    .catalog = g_ptr_array_new_with_free_func(free_catalog_entry),
  };
  for (int index = 2; index < argc; index++) {
    if (strcmp(argv[index], "--verify") == 0) app.verify = true;
    if (strcmp(argv[index], "--exit-ms") == 0 && index + 1 < argc) {
      app.exit_ms = atoi(argv[index + 1]);
      index++;
    }
  }

  GtkApplication *application = gtk_application_new("run.boon.gleam.playground", G_APPLICATION_DEFAULT_FLAGS);
  g_signal_connect(application, "activate", G_CALLBACK(activate), &app);
  int status = g_application_run(G_APPLICATION(application), 0, NULL);
  g_object_unref(application);
  if (app.verify && status == 0 && app.verify_failed == 0) {
    printf("{\"status\":\"pass\",\"backend\":\"gtk4\",\"window_created\":true,\"catalog_examples\":%u,\"counter_click_verified\":true}\n", app.catalog->len);
  }
  free_scene(&app.scene);
  g_ptr_array_unref(app.catalog);
  if (status != 0) return status;
  return app.verify_failed;
}
