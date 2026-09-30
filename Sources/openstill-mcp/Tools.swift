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
         delete_mask_layer removes it. The answer shows the photo with the selected area in red, plus coverage and bounds, so check it and adjust. \
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
        ("preview_mask", "See where a mask layer applies: the photo with that layer's selection in red, with its coverage and bounds.",
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
enum Prompts {
    static let all: [(name: String, description: String, arguments: [(name: String, description: String, required: Bool)])] = [
        ("edit_like", "Edit the open photo in a described style.", [("style", "The look you want, e.g. \"moody film, warm highlights\".", true)]),
        ("grade_folder", "Give every photo in a folder a consistent grade.", [("folder", "The folder's path.", true), ("style", "The look you want.", false)]),
        ("find_luts", "Find free LUTs for a style and add them to OpenStill.", [("style", "The look, e.g. \"teal and orange\".", true)]),
    ]
    static var list: [[String: Any]] {
        all.map { p in ["name": p.name, "description": p.description,
                        "arguments": p.arguments.map { ["name": $0.name, "description": $0.description, "required": $0.required] }] }
    }
    static func text(_ name: String, _ arguments: [String: String]) -> String? {
        func value(_ key: String) -> String { arguments[key] ?? "" }
        switch name {
        case "edit_like":
            return """
            Edit the photo open in OpenStill so it looks like this: \(value("style")).
            First call get_photo and preview to see it. Then change a few sliders at a time with set_adjustments, checking with preview after each step. \
            When only part of the photo needs a change (sky, subject, a corner, the background), use add_mask_layer: look at the red area it returns, \
            fix it with update_mask_layer (move, resize, invert) or delete_mask_layer, and tune its sliders. \
            Finish with preview compare: true to check before against after. Keep it natural unless the style asks otherwise, and explain what you changed.
            """
        case "grade_folder":
            let style = value("style").isEmpty ? "a clean, consistent look" : value("style")
            return """
            Give the photos in \(value("folder")) \(style).
            Call list_photos with that folder, preview a few to understand them, then apply matching set_adjustments to each photo by photo_id. \
            Adjust exposure and white balance per photo so they match each other. Summarize what you did.
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
