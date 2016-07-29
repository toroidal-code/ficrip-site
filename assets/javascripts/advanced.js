//=require 'common'

$(document).ready(function() {
  var theme = $('meta[name=theme]').attr('content');
  var color = theme === 'light' ? 'white' : 'black';

  $('#source-selector').find('option[value="URL"]').prop('selected', true);
  $('select').material_select();

  window.swapCoverField = function (sel){
    if (sel.value == 'URL') {
      $('#cover-file-field').fadeOut(500, function(){
        $('#cover-url-field').fadeIn(500);
        $('input[name="cover_file"]').prop('disabled', true);
      });
      $('input[name="cover_url"]').prop('disabled', false);
      $(':submit').off('click');
      $(':submit').click(formSubmit($('#advanced-form')));
    } else if (sel.value == 'Upload') {
      $('#cover-url-field').fadeOut(500, function(){
        $('#cover-file-field').fadeIn(1000);
        $('input[name="cover_url"]').prop('disabled', true);
      });
      $('input[name="cover_file"]').prop('disabled', false);
    }
  };

  $('.dropdown-button').dropdown({
    inDuration: 300,
    outDuration: 225,
    constrain_width: false, // Does not change width of dropdown to that of the activator
    hover: true, // Activate on hover
    gutter: 0, // Spacing from edge
    belowOrigin: false, // Displays dropdown below the button
    alignment: 'left' // Displays dropdown with edge aligned to the left of button
  });


  var progressBarTemplate = function () {
    // Gross templating, but necessary
    return '<br/>'+
      '<div class="grey ' + theme +'en-3 progress">' +
      '<div class="' + color + ' indeterminate" id=progress style="width: 0"></div>' +
      '</div>'
  };

  if (typeof(window.FormData) !== 'undefined') {
    $(':file').change(function () {
      var file = this.files[0];
      name = file.name;
      size = file.size;
      type = file.type;

      if (file.name.length < 1) {
      } else {
        $(':submit').off('click');

        var xhrCallback = function () {  // custom xhr
          var myXhr = $.ajaxSettings.xhr();
          if (myXhr.upload) { // if upload property exists
            $('form').replaceWith(progressBarTemplate());

            // progressbar
            myXhr.upload.addEventListener('progress', function (event) {
              if (event.lengthComputable) {
                var percentComplete = Math.round(event.loaded / event.total);
                var progressbar = $('#progress');
                if (progressbar.hasClass('indeterminate')) {
                  progressbar.removeClass('indeterminate').addClass('determinate');
                }
                progressbar.css('width', percentComplete.toString() + '%');
              }
            }, false);
          }
          return myXhr;
        };

        $(':submit').click(function (event) {
          $('.material-tooltip').remove();
          event.preventDefault();
          var formData = new FormData($('#advanced-form')[0]);
          for(var pair of formData.entries()) {
            console.log(pair[0]+ ', '+ pair[1]);
          }
          console.log($('#advanced-form'));
          $.ajax({
            url: '/get',  // server script to process data
            type: 'POST',
            data: formData,
            cache: false,
            contentType: false,
            processData: false,
            xhr: xhrCallback,
            success: formSubmitSuccessCallback,
            error: function (event) {
              console.log(event);
              $('form').submit();
            }
          });
          return false;
        });
      }
    });
  }

  // Disconnect the original submit handler
  $(':submit').off('click');
  $(':submit').click(formSubmit($('#advanced-form')));
});