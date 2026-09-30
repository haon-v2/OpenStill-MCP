import Foundation

/// The tools OpenStill offers an AI. Each one is run inside the OpenStill app, through the same code as its own controls,
/// so every edit is one normal undo step and OpenStill stays the only program that saves edits.
enum Tools {
    typealias Schema = [String: Any]

    static func object(_ properties: [String: Schema], required: [String] = []) -> Schema {
        var schema: Schema = ["type": "object", "properties": properties, "additionalProperties": false]
        if !required.isEmpty { schema["required"] = required }
        return schema
    }
    static func string(_ description: String, _ choices: [String]? = nil) -> Schema {
        var schema: Schema = ["type": "string", "description": description]
        if let choices { schema["enum"] = choices }
        return schema
    }
    static func number(_ description: String, minimum: Double? = nil, maximum: Double? = nil) -> Schema {
        var schema: Schema = ["type": "number", "description": description]
        if let minimum { schema["minimum"] = minimum }
        if let maximum { schema["maximum"] = maximum }
        return schema
    }
    static func integer(_ description: String, minimum: Int, maximum: Int) -> Schema {
        ["type": "integer", "description": description, "minimum": minimum, "maximum": maximum]
    }
    static func boolean(_ description: String) -> Schema { ["type": "boolean", "description": description] }
    static func point(_ description: String) -> Schema {
        ["type": "array", "items": ["type": "number", "minimum": 0, "maximum": 1], "minItems": 2, "maxItems": 2, "description": description]
    }

    static let photo = string("The photo's id from list_photos. Leave it out to use the photo open in OpenStill.")
    static let photos: Schema = ["type": "array", "items": ["type": "string"], "description": "Several photo ids from list_photos."]

    /// Slider names and ranges, matching OpenStill's Develop sliders.
    static let sliders: [(name: String, min: Double, max: Double, neutral: Double, help: String)] = [
        ("exposure", -4, 4, 0, "Stops of brightness."),
        ("contrast", 0.5, 1.5, 1, "Smart Contrast: 1 is neutral, 1.5 strongest, 0.5 flattest."),
        ("highlights", -1, 1, 0, "−1 recovers bright areas, +1 brightens them."),
        ("shadows", -1, 1, 0, "−1 deepens shadows, +1 lifts them."),
        ("whites", -1, 1, 0, "Sets the white point."),
        ("blacks", -1, 1, 0, "Sets the black point."),
        ("temperature", 2500, 10000, 6500, "White balance in kelvin; higher is warmer."),
        ("tint", -100, 100, 0, "Positive adds magenta, negative adds green."),
        ("vibrance", -1, 1, 0, "Boosts muted colors more than saturated ones."),
        ("saturation", 0, 2, 1, "1 is neutral, 0 is black and white."),
        ("clarity", -1, 1, 0, "Broad midtone contrast."),
        ("texture", -1, 1, 0, "Medium-sized detail."),
        ("dehaze", -1, 1, 0, "Removes (or adds) haze."),
        ("sharpness", 0, 2, 0, "Sharpening amount."),
        ("noise_reduction", 0, 1, 0, "Luminance noise reduction."),
        ("vignette", -1, 1, 0, "Negative darkens the edges, positive lightens them."),
        ("straighten", -20, 20, 0, "Rotation in degrees."),
        ("lut_amount", 0, 1, 1, "Strength of the applied LUT."),
    ]
    static let maskSliders = ["exposure", "contrast", "highlights", "shadows", "whites", "blacks", "temperature", "tint",
                              "saturation", "clarity", "texture", "dehaze", "sharpness", "noise"]
    static let commands = ["auto_tone", "previous_settings", "reset", "undo", "redo", "rotate", "flip", "reset_crop", "reset_white_balance", "match_lens_profile",
                           "auto_straighten", "level_horizon", "upright", "reset_transform", "remove_lut", "apply_sky", "remove_sky", "flip_sky", "lens_blur_depth",
                           "ai_denoise", "ai_raw_denoise", "ai_detail", "ai_upscale", "ai_erase", "snapshot", "restore_snapshot"]
    static let copySections = ["develop", "curves", "color", "monochrome", "details", "glow", "vignette", "sunrays", "lut", "enhance", "lens", "geometry",
                               "retouch", "presence", "grading", "grain", "transform", "profile"]
    static let radius: Schema = ["description": "Radial: a fraction of the photo, or [width, height].",
                                 "anyOf": [["type": "number"], ["type": "array", "items": ["type": "number"], "minItems": 2, "maxItems": 2]]]

    static var sliderValues: Schema {
        var properties: [String: Schema] = [:]
        for s in sliders { properties[s.name] = number("\(s.help) Neutral \(format(s.neutral)).", minimum: s.min, maximum: s.max) }
        return object(properties)
    }
    static var maskValues: Schema {
        var properties: [String: Schema] = [:]
        for name in maskSliders { properties[name] = number(name == "exposure" ? "Stops, −4…4 (0 is no change)." : name == "noise" ? "0…1 (0 is no change)." : "−1…1 (0 is no change).") }
        return object(properties)
    }
    static func format(_ value: Double) -> String { value == value.rounded() ? String(Int(value)) : String(value) }

    /// Tool name, description, input schema, and whether it only reads (for the client's hints).
    static var all: [(name: String, description: String, schema: Schema, readOnly: Bool)] { [
        ("status", "What OpenStill has open and how many photos are in the library.", object([:]), true),
        ("list_photos", "Find photos in the OpenStill library, newest first.", object([
            "folder": string("Only photos in this folder (and its subfolders)."),
            "text": string("Search file names, titles, captions and keywords."),
            "min_rating": integer("At least this many stars.", minimum: 0, maximum: 5),
            "flag": string("Pick flag.", ["pick", "reject", "none"]),
            "label": string("Color label.", ["red", "yellow", "green", "blue", "purple", "none"]),
            "keyword": string("Has a keyword containing this text."),
            "camera": string("Camera model contains this text."),
            "edited": boolean("Only edited (true) or unedited (false) photos."),
            "captured_after": string("YYYY-MM-DD, inclusive."),
            "captured_before": string("YYYY-MM-DD, inclusive."),
            "limit": integer("How many to return (default 50).", minimum: 1, maximum: 500),
        ]), true),
        ("get_photo", "A photo's details and its current slider values.", object(["photo_id": photo]), true),
        ("open_photo", "Open a photo in OpenStill's Develop view.", object(["photo_id": photo]), false),
        ("preview", "See the photo with its current edits, as a JPEG. With compare: true you get the unedited photo (left) beside the edited one (right), to judge a change. The size is limited in OpenStill's Settings.",
         object(["photo_id": photo, "size": integer("Longest edge in pixels (default 1024).", minimum: 256, maximum: 2048),
                 "compare": boolean("Show before (left) and after (right) side by side.")]), true),
        ("set_adjustments", "Change Develop sliders. Only the sliders you name change; values outside a slider's range are limited to it. One undo step.",
         object(["photo_id": photo, "values": sliderValues], required: ["values"]), false),
        ("auto_tone", "Apply OpenStill's automatic tone to the photo.", object(["photo_id": photo]), false),
        ("apply_preset", "Apply one of OpenStill's presets by name, as shown in its Presets panel (for example \"Vivid\" or \"Warm light\").", object(["photo_id": photo, "name": string("Preset name.")], required: ["name"]), false),
        ("crop", "Crop to a rectangle measured from the photo's top-left corner as fractions (0…1), or pass reset: true to remove the crop.",
         object(["photo_id": photo, "x": number("Left edge.", minimum: 0, maximum: 1), "y": number("Top edge.", minimum: 0, maximum: 1),
                 "width": number("At least 0.05.", minimum: 0.05, maximum: 1), "height": number("At least 0.05.", minimum: 0.05, maximum: 1),
                 "reset": boolean("Remove the crop.")]), false),
        ("reset", "Reset every edit on the photo (one undo step).", object(["photo_id": photo]), false),
        ("undo", "Undo the last edit on the photo.", object(["photo_id": photo]), false),
        ("add_mask_layer", """
         Add a masked adjustment layer to the open photo: its sliders change only the selected area. Kinds: linear (a gradient) and radial (an ellipse) \
         placed by coordinates, or an on-device AI selection (subject, sky, background, people). Layers are safe to try: each is one undo step and \
         delete_mask_layer removes it. The answer shows the photo with the selected area in red beside the selection alone (white = full effect), plus coverage and bounds, so check it and adjust. \
         AI selections take a few seconds; if nothing is found, no layer is added and the reason is given.
         """,
         object(["photo_id": photo,
                 "kind": string("Mask kind.", ["linear", "radial", "subject", "sky", "background", "people"]),
                 "name": string("Layer name."),
                 "values": maskValues,
                 "from": point("Linear: the fully affected point [x, y], as fractions from the top-left."),
                 "to": point("Linear: where the effect has faded out."),
                 "center": point("Radial: center [x, y]."),
                 "radius": radius,
                 "feather": number("Edge softness, 0…1.", minimum: 0, maximum: 1),
                 "invert": boolean("Select everything except the shape."),
                 "size": integer("Longest edge of the returned image.", minimum: 256, maximum: 2048),
                ], required: ["kind"]), false),
        ("list_mask_layers", "The open photo's mask layers: id, name, what they select, whether hidden or inverted, and their slider values.",
         object(["photo_id": photo]), true),
        ("preview_mask", "See where a mask layer applies: the photo with that layer's selection in red, beside the selection alone (white = full effect, black = none), with its coverage and bounds.",
         object(["photo_id": photo, "layer_id": string("Layer id (or exact name) from list_mask_layers."),
                 "size": integer("Longest edge in pixels.", minimum: 256, maximum: 2048)], required: ["layer_id"]), true),
        ("update_mask_layer", "Change a mask layer: its sliders (only the ones you name change), name, hidden, invert, or move and resize a linear or radial shape. One undo step; the answer shows the new selection in red.",
         object(["photo_id": photo, "layer_id": string("Layer id (or exact name) from list_mask_layers."),
                 "values": maskValues, "name": string("New name."), "hidden": boolean("Hide the layer's effect without deleting it."),
                 "invert": boolean("Select everything except the current area."),
                 "from": point("Linear: new fully affected point."), "to": point("Linear: new fade-out point."),
                 "center": point("Radial: new center."), "radius": radius,
                 "feather": number("Edge softness, 0…1 (linear and radial).", minimum: 0, maximum: 1),
                 "size": integer("Longest edge of the returned image.", minimum: 256, maximum: 2048)], required: ["layer_id"]), false),
        ("delete_mask_layer", "Remove a mask layer and its effect (one undo step).",
         object(["photo_id": photo, "layer_id": string("Layer id (or exact name) from list_mask_layers.")], required: ["layer_id"]), false),
        ("rate", "Set the star rating.", object(["photo_id": photo, "photo_ids": photos, "rating": integer("Stars.", minimum: 0, maximum: 5)], required: ["rating"]), false),
        ("flag", "Set the pick flag.", object(["photo_id": photo, "photo_ids": photos, "flag": string("Flag.", ["pick", "reject", "none"])], required: ["flag"]), false),
        ("label", "Set the color label.", object(["photo_id": photo, "photo_ids": photos,
                                                  "label": string("Label.", ["red", "yellow", "green", "blue", "purple", "none"])], required: ["label"]), false),
        ("add_keywords", "Add keywords.", object(["photo_id": photo, "photo_ids": photos,
                                                  "keywords": ["type": "array", "items": ["type": "string"], "description": "Keywords to add."] as Schema], required: ["keywords"]), false),
        ("export", "Export photos with their edits, using the export settings chosen in OpenStill.",
         object(["photo_id": photo, "photo_ids": photos, "folder": string("Destination folder (default: OpenStill's export folder)."),
                 "format": string("File format.", ["jpeg", "png", "tiff", "heif"]),
                 "long_edge": integer("Longest edge in pixels.", minimum: 64, maximum: 20000)]), false),
        ("edit_reference", "What every part of the edit document means (ranges, neutral values, coordinates) and the commands run_command offers. Read it once before using edit.",
         object([:]), true),
        ("get_edits", "The photo's complete edit: every Develop section (basic, curves, HSL, color grading, detail, glow, grain, point color, lens, transform, calibration, effects, masks and layers, retouch…), plus its LUT, sky and snapshots.",
         object(["photo_id": photo]), true),
        ("edit", "Change any part of the edit with a JSON merge patch on the get_edits document: give only what changes, nested the same way; null removes a part; lists are replaced whole. Values are limited to their ranges like the sliders. One undo step; the answer lists what changed and anything limited.",
         object(["photo_id": photo, "patch": ["type": "object", "description": "For example {\"advanced\": {\"glow\": {\"amount\": 40}, \"grain\": {\"amount\": 0.3}}, \"exposure\": 0.2}."] as Schema],
                required: ["patch"]), false),
        ("run_command", "Do what a Develop button does and wait for it to finish: auto_tone, previous_settings, reset, undo, redo, rotate, flip, reset_crop, reset_white_balance, match_lens_profile, auto_straighten, level_horizon, upright (auto|level|vertical|full|off), reset_transform, remove_lut, apply_sky (sky id), remove_sky, flip_sky, lens_blur_depth (camera|ai|subject|remove), ai_denoise, ai_raw_denoise, ai_detail, ai_upscale, ai_erase (inside advanced.masks.Erase), snapshot (name), restore_snapshot (id).",
         object(["photo_id": photo, "name": string("Command name.", commands), "argument": string("For commands that take one (see the list).")], required: ["name"]), false),
        ("copy_edits", "Copy and paste settings: the chosen sections of one photo's edit onto other photos, like Copy Settings / Sync. Sections: develop, curves, color, monochrome, details, glow, vignette, sunrays, lut, enhance, lens, geometry, retouch, presence, grading, grain, transform, profile (default: all except lens, geometry, retouch, transform). Undo with the library's Undo Batch.",
         object(["from_photo_id": string("The photo to copy from (default: the open photo)."), "to_photo_ids": photos,
                 "sections": ["type": "array", "items": ["type": "string", "enum": copySections], "description": "Which sections to paste."] as Schema,
                 "masks": boolean("Also paste mask layers and masks.")], required: ["to_photo_ids"]), false),
        ("list_presets", "OpenStill's presets (name, category, description) for apply_preset.", object([:]), true),
        ("list_skies", "The replacement skies (id, name, category) for run_command apply_sky.", object([:]), true),
        ("list_luts", "The LUTs (color looks) installed in OpenStill, with their creator and license.",
         object(["category": string("Only this category.")]), true),
        ("apply_lut", "Apply a LUT from list_luts.", object(["photo_id": photo, "id": string("LUT id."),
                                                            "amount": number("Strength, 0…1.", minimum: 0, maximum: 1)], required: ["id"]), false),
        ("import_lut", "Download a free LUT (.cube, or a .zip of .cube files) over https and add it to OpenStill. The license must be stated and free (for example CC0, CC BY, MIT); others are refused.",
         object(["url": string("https download link."), "name": string("Name to show."), "creator": string("Who made it."),
                 "license": string("The license stated by the creator."), "source_page": string("The page where it's offered.")],
                required: ["url", "license", "source_page"]), false),
    ] }

    static var list: [[String: Any]] {
        all.map { tool in
            ["name": tool.name, "description": tool.description, "inputSchema": tool.schema,
             "annotations": ["readOnlyHint": tool.readOnly, "destructiveHint": tool.name == "reset", "openWorldHint": tool.name == "import_lut"]]
        }
    }
    static func exists(_ name: String) -> Bool { all.contains { $0.name == name } }
}

/// Ready-made requests the AI app can offer.
/// How to edit well and quickly. Sent to every AI app as the server's instructions and included in each prompt.
enum Guidelines {
    static let speed = """
    Working quickly:
    - Read edit_reference once per conversation, not per photo. Read get_edits once, then work from what edit returns.
    - Make each edit call count: change every related section in ONE patch (for example exposure, highlights, white balance, \
    HSL and color grading together) instead of one slider per call.
    - Look small while working: preview with size 512–768, and only the final check at 1024 or more with compare: true.
    - Aim for 2–4 passes per photo: a global pass, a color pass, local masks if needed, then finishing. Don't preview after every tiny change.
    - For a series, perfect one photo, then copy_edits its settings to the others and only correct exposure and white balance per photo.
    - Start from a preset or LUT (list_presets, list_luts) when the requested look is close to one, then refine.
    - run_command waits for its work to finish; don't poll. On-device AI tools (denoise, upscale, erase, sky) are slow: use them only when they matter.
    """
    static let craft = """
    Edit like a professional photographer:
    - Look first. Before changing anything, preview the photo and say in a sentence what it needs: \
    exposure and dynamic range, white balance and color casts, the subject and where the eye should go, distractions, horizon and crop.
    - Work in the order a photographer does: profile and lens corrections → white balance → exposure and tone (highlights, shadows, whites, blacks) → \
    presence (texture, clarity, dehaze) → color (vibrance, HSL, point color) → color grading → local adjustments with masks → detail and noise → \
    effects (vignette, grain, glow) → crop and straighten last.
    - Protect the ends of the tones: keep highlight detail (skies, skin, white clothes) and keep shadows from going muddy or crushed unless it's the style.
    - Keep skin natural: skin tones sit in the orange band; never let them go green, magenta or orange-plastic. Be gentle with clarity and texture on faces.
    - Restraint reads as quality. Small moves, then check. Global saturation rarely beats vibrance and targeted HSL. \
    Glow, grain, clarity, dehaze and vignette are seasoning: a little goes a long way.
    - Guide the eye with light: brighten and warm the subject slightly, calm the edges and distractions with masks, keep the horizon level.
    - Match the intent of the photo (portrait, landscape, street, product, event) and of the person's request; if the style is unclear, choose a clean, natural edit.
    - Compare before and after (preview compare: true) and judge it as a whole at the end; undo or soften anything that looks processed.
    - Explain what you did in a photographer's terms (for example "cooled the shadows and warmed the highlights for separation"), briefly.
    """
    static let instructions = """
    OpenStill is a photo editor on this Mac; these tools do everything its Develop panel can. \
    Start with status or list_photos, and preview to look. Basic sliders: set_adjustments. Everything else (curves, HSL, color grading, glow, grain, \
    point color, detail, lens, transform, calibration, retouch, masks, lens blur…): read edit_reference once, then get_edits and edit (a JSON merge patch). \
    Buttons (auto tone, Upright, AI noise removal, erase, skies, snapshots): run_command. Copy settings between photos: copy_edits. \
    Local changes: add_mask_layer, then look at the red area it returns. Every change is one undo step.

    """ + speed + "\n" + craft
}

enum Prompts {
    static let all: [(name: String, description: String, arguments: [(name: String, description: String, required: Bool)])] = [
        ("pro_edit", "Edit the open photo the way a professional photographer would, quickly.", [("goal", "Optional: the look or use, e.g. \"natural portrait\" or \"moody landscape for print\".", false)]),
        ("quick_fix", "A fast, natural correction of the open photo in one or two passes.", []),
        ("edit_like", "Edit the open photo in a described style.", [("style", "The look you want, e.g. \"moody film, warm highlights\".", true)]),
        ("match_look", "Give the open photo the look of another photo in the library.", [("reference_photo_id", "The photo whose look to match (from list_photos).", true)]),
        ("portrait_retouch", "Professional portrait finishing: skin, eyes, light on the face, background.", []),
        ("landscape_polish", "Landscape finishing: sky, depth, color separation, detail.", []),
        ("grade_folder", "Give every photo in a folder a consistent grade.", [("folder", "The folder's path.", true), ("style", "The look you want.", false)]),
        ("cull_and_rate", "Look through a folder and rate, flag and label the best photos like a photographer culling a shoot.", [("folder", "The folder's path.", true)]),
        ("find_luts", "Find free LUTs for a style and add them to OpenStill.", [("style", "The look, e.g. \"teal and orange\".", true)]),
    ]
    static var list: [[String: Any]] {
        all.map { p in ["name": p.name, "description": p.description,
                        "arguments": p.arguments.map { ["name": $0.name, "description": $0.description, "required": $0.required] }] }
    }
    static func text(_ name: String, _ arguments: [String: String]) -> String? {
        func value(_ key: String) -> String { arguments[key] ?? "" }
        let guides = "\n\n" + Guidelines.speed + "\n" + Guidelines.craft
        switch name {
        case "pro_edit":
            let goal = value("goal").isEmpty ? "a clean, natural, professional result that suits the photo" : value("goal")
            return """
            Edit the photo open in OpenStill like a professional photographer. Goal: \(goal).
            1. preview (size 768) and get_edits. In one or two sentences, say what the photo needs and what you'll do.
            2. Global pass in ONE edit call: lens/profile if needed, white balance, exposure, highlights, shadows, whites, blacks, presence, vibrance.
            3. Color pass in ONE edit call: HSL bands, point color if a specific color needs care, color grading for mood.
            4. Local pass only if it helps: add_mask_layer for the subject, sky or background (check the red area), then tune with update_mask_layer.
            5. Finish in ONE edit call: detail/noise, subtle vignette or grain if it suits, crop and straighten.
            6. preview compare: true at 1024. Soften anything overdone, then summarize the edit briefly in photographer's terms.
            """ + guides
        case "quick_fix":
            return """
            Give the photo open in OpenStill a fast, natural correction.
            preview (size 640), then make ONE edit call that fixes exposure, white balance, highlights and shadows, whites and blacks, and adds a touch of \
            vibrance and texture; straighten if the horizon is tilted (run_command level_horizon or auto_straighten). \
            Check once with preview compare: true and make at most one small correction. Say in one line what you changed.
            """ + guides
        case "edit_like":
            return """
            Edit the photo open in OpenStill so it looks like this: \(value("style")).
            preview (size 768) and get_edits, then translate the style into concrete choices (tone curve shape, white balance, HSL, color grading, \
            grain or glow) and apply them in as few edit calls as possible. Use a preset or LUT as a starting point if one is close (list_presets, list_luts). \
            Use add_mask_layer where only part of the photo should change. Finish with preview compare: true and explain the look in photographer's terms.
            """ + guides
        case "match_look":
            return """
            Match the look of photo \(value("reference_photo_id")) on the photo open in OpenStill.
            Preview both (size 640) and read get_edits for the reference. Copy what defines the look — tone curve, HSL, color grading, effects, profile — \
            with copy_edits (sections: curves, color, grading, grain, glow, vignette, profile), then correct exposure and white balance for this photo \
            in one edit call so the two sit together. Check with preview compare: true.
            """ + guides
        case "portrait_retouch":
            return """
            Finish the portrait open in OpenStill like a portrait photographer.
            preview (size 768). Global: flattering exposure, clean white balance with natural skin (orange band hue/saturation/lightness in HSL, gently), \
            soft contrast. Local: add_mask_layer subject (or people) to lift the person slightly, and a separate layer to calm a busy or bright background. \
            Keep texture and clarity on skin at or slightly below 0; add a little sharpness to the eyes only if a small radial mask covers them. \
            Remove small blemishes with advanced.retouch heal strokes only if clearly distracting. Check with preview compare: true; the person must still look like themselves.
            """ + guides
        case "landscape_polish":
            return """
            Finish the landscape open in OpenStill like a landscape photographer.
            preview (size 768). Global: recover the sky (highlights −, whites to taste), open shadows, add depth with a gentle S-curve, a little dehaze and texture. \
            Color: separate sky and land with HSL (blues and aquas vs greens and yellows) and color grading (cooler shadows, warmer highlights, subtly). \
            Local: a sky mask (add_mask_layer sky, or a linear mask from the top) to balance it with the land; a soft radial on the main subject. \
            Level the horizon. Finish with detail, and a light vignette only if it helps. Check with preview compare: true.
            """ + guides
        case "grade_folder":
            let style = value("style").isEmpty ? "a clean, consistent look" : value("style")
            return """
            Give the photos in \(value("folder")) \(style).
            list_photos with that folder and preview 3–4 of them (size 512) to see the range. Perfect the most typical photo first (as in pro_edit), \
            then copy_edits its look to the rest (sections: curves, color, grading, grain, glow, vignette, profile). Then go through the others and \
            correct only exposure and white balance in one edit call each so the set matches. Summarize what you did.
            """ + guides
        case "cull_and_rate":
            return """
            Cull the shoot in \(value("folder")) like a photographer.
            list_photos with that folder, preview each at size 384. Judge focus on the subject, expression and moment, composition, exposure and \
            duplicates (keep the best of a burst). Rate with rate: 5 for portfolio picks, 4 strong, 3 usable, 1–2 weak; flag pick the keepers and \
            reject the clear failures (blur, closed eyes, misfires). Work in batches (rate and flag take several photo_ids). Summarize the picks.
            """
        case "find_luts":
            return """
            Find free LUTs (.cube files) for this style: \(value("style")).
            Search the web for ones whose creators state a free license (such as CC0, CC BY or MIT) on the download page. \
            For each good match call import_lut with its https download link, the license exactly as stated, the creator and the page you found it on. \
            Skip anything without a clear free license. Then list what you added.
            """
        default: return nil
        }
    }
}
