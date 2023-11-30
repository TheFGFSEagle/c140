var dialogs = {};

dialogs.AircraftConfigurationDialog = {
	new: func {
		var obj = {
			parents: [dialogs.AircraftConfigurationDialog],
			window: canvas.Window.new(size: [250, 100], type: "dialog", destroy_on_close: 0)
							.setTitle("Aircraft configuration")
							.setBool("resize", 1),
			equipmentNode: props.globals.getNode("sim/equipment"),
		};
		obj.astrotechLC2Node = obj.equipmentNode.getNode("astrotech-lc2", 1);
		obj.navRadioNode = obj.equipmentNode.getNode("nav-radio", 1);
		
		obj.canvas = obj.window.getCanvas(create: 1).set("background", canvas.style.getColor("bg_color"));
		obj.root = obj.canvas.createGroup();
		obj.layout = canvas.VBoxLayout.new();
		obj.canvas.setLayout(obj.layout);
		
		obj.tabs = canvas.gui.widgets.TabWidget.new(obj.root, canvas.style, {});
		obj.tabsContent = obj.tabs.getContent();
		obj.layout.addItem(obj.tabs);
		
		obj.equipmentTab = canvas.VBoxLayout.new();
		obj.tabs.addTab("equipment", "Equipment", obj.equipmentTab);
		
		obj.astrotechLC2Checkbox = canvas.gui.widgets.PropertyCheckBox.new(
			obj.tabsContent, canvas.style, {"node": obj.astrotechLC2Node, "label-position": "left"}
		)
						.setText("Astrotech LC-2 digital clock:");
		obj.equipmentTab.addItem(obj.astrotechLC2Checkbox);
		
		obj.navRadioCheckbox = canvas.gui.widgets.PropertyCheckBox.new(
			obj.tabsContent, canvas.style, {"node": obj.navRadioNode, "label-position": "left"}
		)
						.setText("NAV Radio:");
		obj.equipmentTab.addItem(obj.navRadioCheckbox);
		return obj;
	},
	
	show: func {
		me.window.show();
	},
	
	hide: func {
		me.window.hide();
	},
	
	del: func {
		var widget = me.layout.takeAt(0);
		while (widget) {
			widget.del();
			widget = me.layout.takeAt(0);
		}
		me.window.del();
		dialogs.aircraftConfigurationDialog = nil;
	},
};

dialogs.aircraftConfigurationDialog = dialogs.AircraftConfigurationDialog.new();

