var formSubmitSuccessCallback = function (data) {
  data = $.parseJSON(data);
  window.params = data;
  var fallbackURL = '/get' + '?' + $.param(window.params);
  $.ajax('/get', {
    data: data,
    success: function (data) {
      $('main').add('footer').fadeOut(600).promise().done(function () {
        $('#page-content').replaceWith(data);
        $('#footer-items').remove();
        $('#about-link').attr('target', '_blank');
        $('#title').add('#subtitle').css('visibility', 'hidden');
      });
      // Load the script for downloading
      $.ajax('assets/download.js', {
        dataType: "script",
        error: function () { window.location = fallbackURL }
      });
    },
    error: function () {  window.location = fallbackURL }
  });
};

var formSubmit = function (element) {
  return function (event) {
    event.preventDefault();
    console.log(element.serialize());
    $('.material-tooltip').remove();
    $.ajax({
      url: '/get',  // server script to process data
      type: 'POST',
      data: element.serialize(),
      // Ajax events
      success: formSubmitSuccessCallback,
      error: function () { element.submit(); }
    });
    return false;
  };
};
