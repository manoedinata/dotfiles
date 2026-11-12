// List toplevels with the outputs they are on, via wlr-foreign-toplevel-management.
// Output: one line per (toplevel, output): "<output-name>\t<app_id>\t<title>"
#define _GNU_SOURCE
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <wayland-client.h>
#include "wlr-foreign-toplevel-management-unstable-v1-client-protocol.h"

#define MAX_OUT 16

struct output {
	struct wl_output *wl;
	char *name;
};

struct toplevel {
	char *app_id, *title;
	struct wl_output *outs[MAX_OUT];
	int n_outs;
	struct toplevel *next;
};

static struct output outputs[MAX_OUT];
static int n_outputs;
static struct zwlr_foreign_toplevel_manager_v1 *manager;
static struct toplevel *toplevels;

static void out_geometry(void *d, struct wl_output *o, int32_t x, int32_t y, int32_t pw, int32_t ph,
		int32_t sp, const char *make, const char *model, int32_t t) {}
static void out_mode(void *d, struct wl_output *o, uint32_t f, int32_t w, int32_t h, int32_t r) {}
static void out_done(void *d, struct wl_output *o) {}
static void out_scale(void *d, struct wl_output *o, int32_t s) {}
static void out_name(void *d, struct wl_output *o, const char *name) {
	struct output *out = d;
	free(out->name);
	out->name = strdup(name);
}
static void out_description(void *d, struct wl_output *o, const char *desc) {}

static const struct wl_output_listener output_listener = {
	.geometry = out_geometry, .mode = out_mode, .done = out_done,
	.scale = out_scale, .name = out_name, .description = out_description,
};

static void tl_title(void *d, struct zwlr_foreign_toplevel_handle_v1 *h, const char *s) {
	struct toplevel *t = d; free(t->title); t->title = strdup(s);
}
static void tl_app_id(void *d, struct zwlr_foreign_toplevel_handle_v1 *h, const char *s) {
	struct toplevel *t = d; free(t->app_id); t->app_id = strdup(s);
}
static void tl_output_enter(void *d, struct zwlr_foreign_toplevel_handle_v1 *h, struct wl_output *o) {
	struct toplevel *t = d;
	if (t->n_outs < MAX_OUT) t->outs[t->n_outs++] = o;
}
static void tl_output_leave(void *d, struct zwlr_foreign_toplevel_handle_v1 *h, struct wl_output *o) {
	struct toplevel *t = d;
	for (int i = 0; i < t->n_outs; i++)
		if (t->outs[i] == o) { t->outs[i] = t->outs[--t->n_outs]; break; }
}
static void tl_state(void *d, struct zwlr_foreign_toplevel_handle_v1 *h, struct wl_array *a) {}
static void tl_done(void *d, struct zwlr_foreign_toplevel_handle_v1 *h) {}
static void tl_closed(void *d, struct zwlr_foreign_toplevel_handle_v1 *h) {}
static void tl_parent(void *d, struct zwlr_foreign_toplevel_handle_v1 *h,
		struct zwlr_foreign_toplevel_handle_v1 *p) {}

static const struct zwlr_foreign_toplevel_handle_v1_listener toplevel_listener = {
	.title = tl_title, .app_id = tl_app_id, .output_enter = tl_output_enter,
	.output_leave = tl_output_leave, .state = tl_state, .done = tl_done,
	.closed = tl_closed, .parent = tl_parent,
};

static void mgr_toplevel(void *d, struct zwlr_foreign_toplevel_manager_v1 *m,
		struct zwlr_foreign_toplevel_handle_v1 *h) {
	struct toplevel *t = calloc(1, sizeof(*t));
	t->next = toplevels;
	toplevels = t;
	zwlr_foreign_toplevel_handle_v1_add_listener(h, &toplevel_listener, t);
}
static void mgr_finished(void *d, struct zwlr_foreign_toplevel_manager_v1 *m) {}

static const struct zwlr_foreign_toplevel_manager_v1_listener manager_listener = {
	.toplevel = mgr_toplevel, .finished = mgr_finished,
};

static void reg_global(void *d, struct wl_registry *r, uint32_t name, const char *iface, uint32_t ver) {
	if (strcmp(iface, wl_output_interface.name) == 0 && n_outputs < MAX_OUT && ver >= 4) {
		struct output *out = &outputs[n_outputs++];
		out->wl = wl_registry_bind(r, name, &wl_output_interface, 4);
		wl_output_add_listener(out->wl, &output_listener, out);
	} else if (strcmp(iface, zwlr_foreign_toplevel_manager_v1_interface.name) == 0) {
		manager = wl_registry_bind(r, name, &zwlr_foreign_toplevel_manager_v1_interface,
				ver < 3 ? ver : 3);
		zwlr_foreign_toplevel_manager_v1_add_listener(manager, &manager_listener, NULL);
	}
}
static void reg_remove(void *d, struct wl_registry *r, uint32_t name) {}

static const struct wl_registry_listener registry_listener = {
	.global = reg_global, .global_remove = reg_remove,
};

int main(void) {
	struct wl_display *dpy = wl_display_connect(NULL);
	if (!dpy) { fprintf(stderr, "cannot connect to wayland display\n"); return 1; }
	struct wl_registry *reg = wl_display_get_registry(dpy);
	wl_registry_add_listener(reg, &registry_listener, NULL);
	wl_display_roundtrip(dpy); // globals
	if (!manager) { fprintf(stderr, "wlr-foreign-toplevel-management not supported\n"); return 1; }
	wl_display_roundtrip(dpy); // output names, toplevel handles
	wl_display_roundtrip(dpy); // toplevel properties

	for (struct toplevel *t = toplevels; t; t = t->next) {
		for (int i = 0; i < t->n_outs; i++) {
			const char *oname = "?";
			for (int j = 0; j < n_outputs; j++)
				if (outputs[j].wl == t->outs[i] && outputs[j].name) oname = outputs[j].name;
			printf("%s\t%s\t%s\n", oname, t->app_id ? t->app_id : "", t->title ? t->title : "");
		}
	}
	wl_display_disconnect(dpy);
	return 0;
}
