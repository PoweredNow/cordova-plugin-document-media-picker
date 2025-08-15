var exec = require('cordova/exec');

var DocMediaPicker = {
  /**
   * Show a picker dialog.
   * @param {Object} [options]
   * @param {('document'|'media')} [options.mode='document'] - Which picker to show
   * @param {boolean} [options.multiple=true] - Allow multiple selection when supported
   * @param {string[]} [options.mimeTypes] - Optional MIME type filters (Android/iOS document picker)
   * @param {('images'|'videos'|'all')} [options.mediaTypes='all'] - Media filter for media picker
   * @param {number} [options.selectionLimit=0] - Maximum number of items to select (0 = unlimited where supported)
   * @returns {Promise<Array<{uri:string,name?:string,size?:number,mime?:string,width?:number,height?:number,createdAt?:number,modifiedAt?:number}>>}
   */
  showPicker: function (options) {
    var opts = options || {};
    if (typeof opts.mode !== 'string') opts.mode = 'document';
    if (typeof opts.multiple !== 'boolean') opts.multiple = true;
    if (typeof opts.mediaTypes !== 'string') opts.mediaTypes = 'all';
    if (typeof opts.selectionLimit !== 'number') opts.selectionLimit = 0;

    return new Promise(function (resolve, reject) {
      exec(resolve, reject, 'DocMediaPicker', 'showPicker', [opts]);
    });
  }
};

module.exports = DocMediaPicker;
