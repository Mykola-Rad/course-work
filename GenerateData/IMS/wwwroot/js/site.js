// Please see documentation at https://learn.microsoft.com/aspnet/core/client-side/bundling-and-minification
// for details on configuring this project to bundle and minify static web assets.
function initializeAutocomplete() {
    $('[data-autocomplete="true"]').each(function () {
        const $input = $(this);
        const autocompleteUrl = $input.data('autocomplete-url');
        const minLength = $input.data('autocomplete-min-length') || 1; 
        const listSelector = $input.data('autocomplete-list-target');
        const $list = $(listSelector);

        if (!autocompleteUrl || !$list || $list.length === 0) {
            console.warn('Autocomplete init failed: URL or List target missing for input:', $input);
            return; 
        }

        $input.on('input', function () {
            const query = $input.val();
            if (query.length < minLength) {
                $list.empty().hide();
                return;
            }

            $.getJSON(autocompleteUrl, { term: query }, function (data) {
                $list.empty(); 
                if (data && data.length > 0) {
                    data.forEach(function (item) {
                        $list.append(
                            $('<li class="list-group-item list-group-item-action p-1"></li>')
                                .text(item) 
                                .data('value', item) 
                        );
                    });
                    $list.show();
                } else {
                    $list.hide(); 
                }
            });
        });

        $list.on('click', 'li', function () {
            const selectedValue = $(this).data('value') || $(this).text(); 
            $input.val(selectedValue); 
            $list.empty().hide(); 
            $input.trigger('change');
        });
    });

    $(document).off('click.autocompleteClose').on('click.autocompleteClose', function (e) {
        if (!$(e.target).closest('[data-autocomplete="true"], [data-autocomplete-list-target]').length) {
            $('[data-autocomplete-list-target]').each(function () {
                const listSelector = $(this).data('autocomplete-list-target');
                $(listSelector).empty().hide();
            });
        }
    });
}
function initializeResetButtons() {
    $(document).on('click', '[data-reset-form-target]', function () {
        const targetFormSelector = $(this).data('reset-form-target');
        const $form = $(targetFormSelector);

        if ($form.length) {
            $form.find('input[type="text"], input[type="search"], input[type="email"], input[type="password"], textarea').val('');
            $form.find('select').prop('selectedIndex', 0); 
            $form.find('input[type="checkbox"], input[type="radio"]').prop('checked', false);
        } else {
            console.warn('Reset button clicked, but target form not found:', targetFormSelector);
        }
    });
}

$(document).ready(function () {
    const sidebarToggleBtn = $('#sidebarToggle');
    const body = $('body');
    const sidebarStateKey = 'sidebarCollapsedState';

    function applySidebarState() {
        if (localStorage.getItem(sidebarStateKey) === 'true') {
            body.addClass('sidebar-collapsed');
        } else {
            body.removeClass('sidebar-collapsed');
        }
    }

    applySidebarState();

    sidebarToggleBtn.on('click', function () {
        body.toggleClass('sidebar-collapsed');
        if (body.hasClass('sidebar-collapsed')) {
            localStorage.setItem(sidebarStateKey, 'true');
        } else {
            localStorage.removeItem(sidebarStateKey);
        }
    });
    initializeAutocomplete();
    initializeResetButtons();
});