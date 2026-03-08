import Toybox.Application;
import Toybox.WatchUi;

class VaultBoyApp extends Application.AppBase {

    function initialize() {
        AppBase.initialize();
    }

    // This is where the Manifest "entry" looks!
    function getInitialView() {
        return [ new VaultBoyView() ]; 
    }
}