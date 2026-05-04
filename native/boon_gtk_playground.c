#include <gtk/gtk.h>
#include <stdbool.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

typedef struct {
  char *json;
  bool verify;
  int exit_ms;
} AppConfig;

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

static gboolean quit_verify(gpointer app) {
  g_application_quit(G_APPLICATION(app));
  return G_SOURCE_REMOVE;
}

static GtkWidget *label_block(const char *title, const char *value) {
  GtkWidget *box = gtk_box_new(GTK_ORIENTATION_VERTICAL, 8);
  GtkWidget *heading = gtk_label_new(title);
  gtk_widget_add_css_class(heading, "heading");
  gtk_label_set_xalign(GTK_LABEL(heading), 0.0f);
  gtk_box_append(GTK_BOX(box), heading);

  GtkWidget *view = gtk_text_view_new();
  gtk_text_view_set_editable(GTK_TEXT_VIEW(view), false);
  gtk_text_view_set_cursor_visible(GTK_TEXT_VIEW(view), false);
  gtk_text_view_set_wrap_mode(GTK_TEXT_VIEW(view), GTK_WRAP_WORD_CHAR);
  gtk_text_buffer_set_text(gtk_text_view_get_buffer(GTK_TEXT_VIEW(view)), value, -1);
  gtk_widget_set_vexpand(view, true);
  gtk_box_append(GTK_BOX(box), view);
  return box;
}

static void activate(GtkApplication *app, gpointer user_data) {
  AppConfig *config = (AppConfig *)user_data;
  char *example = json_string(config->json, "example");
  char *title = json_string(config->json, "title");
  char *source_path = json_string(config->json, "source_path");
  char *snapshot = json_string(config->json, "snapshot_text");
  char *source = json_string(config->json, "source_preview");

  GtkWidget *window = gtk_application_window_new(app);
  gtk_window_set_title(GTK_WINDOW(window), title[0] ? title : "Boon Gleam Native Playground");
  gtk_window_set_default_size(GTK_WINDOW(window), 1280, 820);

  GtkWidget *root = gtk_box_new(GTK_ORIENTATION_HORIZONTAL, 0);
  gtk_window_set_child(GTK_WINDOW(window), root);

  GtkWidget *sidebar = gtk_box_new(GTK_ORIENTATION_VERTICAL, 12);
  gtk_widget_set_size_request(sidebar, 250, -1);
  gtk_widget_add_css_class(sidebar, "sidebar");
  GtkWidget *brand = gtk_label_new("Boon Gleam");
  gtk_widget_add_css_class(brand, "title-1");
  gtk_label_set_xalign(GTK_LABEL(brand), 0.0f);
  GtkWidget *example_label = gtk_label_new(example);
  gtk_label_set_xalign(GTK_LABEL(example_label), 0.0f);
  gtk_box_append(GTK_BOX(sidebar), brand);
  gtk_box_append(GTK_BOX(sidebar), example_label);
  gtk_box_append(GTK_BOX(root), sidebar);

  GtkWidget *preview = gtk_box_new(GTK_ORIENTATION_VERTICAL, 12);
  gtk_widget_set_hexpand(preview, true);
  gtk_widget_set_vexpand(preview, true);
  GtkWidget *preview_title = gtk_label_new(title);
  gtk_widget_add_css_class(preview_title, "title-2");
  gtk_label_set_xalign(GTK_LABEL(preview_title), 0.0f);
  gtk_box_append(GTK_BOX(preview), preview_title);
  gtk_box_append(GTK_BOX(preview), label_block("Runtime Snapshot", snapshot));
  gtk_box_append(GTK_BOX(root), preview);

  GtkWidget *source_panel = gtk_box_new(GTK_ORIENTATION_VERTICAL, 8);
  gtk_widget_set_size_request(source_panel, 390, -1);
  GtkWidget *source_heading = gtk_label_new(source_path);
  gtk_label_set_xalign(GTK_LABEL(source_heading), 0.0f);
  gtk_box_append(GTK_BOX(source_panel), source_heading);
  gtk_box_append(GTK_BOX(source_panel), label_block("Source", source));
  gtk_box_append(GTK_BOX(root), source_panel);

  GtkCssProvider *css = gtk_css_provider_new();
  gtk_css_provider_load_from_string(css,
    ".sidebar{background:#20302f;color:#f4f2eb;padding:24px;}"
    "box{padding:18px;} textview{font-family:monospace;font-size:13px;}"
    ".heading{font-weight:700;} .title-1{font-size:26px;font-weight:800;}"
    ".title-2{font-size:22px;font-weight:700;}");
  gtk_style_context_add_provider_for_display(
    gdk_display_get_default(),
    GTK_STYLE_PROVIDER(css),
    GTK_STYLE_PROVIDER_PRIORITY_APPLICATION);

  gtk_window_present(GTK_WINDOW(window));
  if (config->verify) {
    g_timeout_add(config->exit_ms, quit_verify, app);
  }

  free(example);
  free(title);
  free(source_path);
  free(snapshot);
  free(source);
}

int main(int argc, char **argv) {
  if (argc < 2) {
    fprintf(stderr, "usage: boon_gtk_playground SCENE_JSON [--verify] [--exit-ms N]\n");
    return 2;
  }
  AppConfig config = {
    .json = read_file(argv[1]),
    .verify = false,
    .exit_ms = 800,
  };
  for (int index = 2; index < argc; index++) {
    if (strcmp(argv[index], "--verify") == 0) config.verify = true;
    if (strcmp(argv[index], "--exit-ms") == 0 && index + 1 < argc) {
      config.exit_ms = atoi(argv[index + 1]);
      index++;
    }
  }

  GtkApplication *app = gtk_application_new("run.boon.gleam.playground", G_APPLICATION_DEFAULT_FLAGS);
  g_signal_connect(app, "activate", G_CALLBACK(activate), &config);
  int status = g_application_run(G_APPLICATION(app), 0, NULL);
  g_object_unref(app);
  if (config.verify && status == 0) {
    printf("{\"status\":\"pass\",\"backend\":\"gtk4\",\"window_created\":true}\n");
  }
  free(config.json);
  return status;
}
