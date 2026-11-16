//
//  main.swift
//  firstMacOS
//
//  Created by Boris Barbulovski on 23.3.23.
//

import Cocoa

let app = NSApplication.shared
MMFont.registerBundledFonts()
let delegate = AppDelegate()
app.delegate = delegate

app.run()
