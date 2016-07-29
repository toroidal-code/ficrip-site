$(document).ready(function () {
  $.fn.exists = function () { return this.length !== 0;  };
  var params = $.parseJSON("#{js_escape_html params.to_json.html_safe}");

  // Connect to the server
  var es = new EventSource('/generate' + '?' + $.param(params));

  // We don't want the user reloading and regenerating the same file,
  // so set our history to the homepage.
  history.replaceState({ uuid: params.uuid }, 'ficrip', '/');

  // Report an error
  es.addEventListener('error', function (e) {
    $('#content').fadeOut(1000, function() {
      $('#content').replaceWith('<div id="content" style="display: none">' + e.data + '</div>');
      $('#content').fadeIn(2000);
    });
  });

  // Update progressbar
  es.addEventListener('progress', function (e) {
    if (e.data === 'null') {
      $('#progress').removeClass('determinate').addClass('indeterminate');
    } else if ( $('.indeterminate').exists() ) {
      $('#progress').removeClass('indeterminate').addClass('determinate').css('width', e.data);
    } else {
      $('#progress').css('width', e.data);
    }
  });

  // Navigate to new URL
  es.addEventListener('url', function (e) { console.log(e.data); window.location = e.data; });

  // Close the connection
  es.addEventListener('close', function () { es.close(); });

  // Add a back button when download is complete
  es.addEventListener('backbutton', function () {
    $('#footeritem').fadeOut(1000, function () {
      $('#footeritem').replaceWith('#{ link_to "back", "/", class: "grey-text" }');
      $('#footeritem').fadeIn(1000);
    });
  });

  // Update the page with the title/author info
  es.addEventListener('info', function (e) {
    var info = $.parseJSON(e.data);
    $('#title').add('#subtitle').fadeOut(1000, function () {
      $('#title').replaceWith('<span id="title" style="display: none">' + info.title + '</span>');
      $('#subtitle').replaceWith('<span id="subtitle" style="display: none">&nbsp; by ' + info.author + '</span>');
      $('#title').add('#subtitle').fadeIn(2000);
    });
  });
});