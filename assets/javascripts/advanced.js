// Used for white pages
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
      $('form').off('submit');

    } else if (sel.value == 'Upload') {
      $('#cover-url-field').fadeOut(500, function(){
        $('#cover-file-field').fadeIn(1000);
        $('input[name="cover_url"]').prop('disabled', true);
      });
      $('input[name="cover_file"]').prop('disabled', false);
      $('form').submit(function(){
        $('.material-tooltip').remove();
        $('form').replaceWith(
          // Gross templating, but necessary
          '<div class="grey ' + theme +'en-3 progress">' +
          '<div class="' + color + ' indeterminate" id=progress style="width: 0"></div>' +
          '</div>'
        );
      });
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
});