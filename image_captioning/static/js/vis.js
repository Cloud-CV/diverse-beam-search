(function() {

beam_search_vis = function() {

var margin = {top: 40, right: 40, bottom: 40, left: 40},
    // dimensions of vis box inside margins
    width = null,
    height = null,
    time_bar_height = 130,
    time_bar_left_margin = margin.left + 5,
    img_width = 200,
    img_prime_text_offset = 20,
    root_hoffset = 20,
    default_link_color = '#ccc',
    group_colors = d3.scale.category10(),
    default_time_color = '#ccc',
    highlight_time_color = '#333',
    line = d3.svg.line()
            .x(function(d) { return d.x; })
            .y(function(d) { return d.y; })
            .interpolate("linear"),
    diagonal = d3.svg.diagonal()
        .projection(function(d) { return [d.y, d.x]; }),
    invisible_div = null;


/*
 * Paramters via query string:
 * data: Name of json file vis data comes from
 * horz_space: Space between levels of the tree (default: 15)
 * trans_time: Time between stages of the animation in millisecs (default: 1000)
 * interact_mode: (default: 'auto')
 *      'interactive' -- Move between time steps with arrow keys
 *      'auto' -- Show all steps of the algorithm without stopping
 * font_size: Font size in px (default: 12px)
 * special_chars: 1 to use "\n" and "\r" instead of white space, 0 for otherwise (default: 0)
 * max_beam_age: Prune beams that are older than this many iterations. If not
 *      provided, this defaults to showing all beams.
 * application:
 *      'char-rnn' -- Input prime text and visualize character RNN sequences
 *      'neuraltalk2' -- Upload images and visualize beam search for captions
 */
var horz_space = parseInt(getParameterByName("horz_space")),
    duration = parseInt(getParameterByName("trans_time")),
    time_bar_duration = 100,
    interact_mode = getParameterByName("mode"),
    font_size = parseInt(getParameterByName("font_size")),
    special_chars = parseInt(getParameterByName("special_chars")),
    max_beam_age = parseInt(getParameterByName("max_beam_age"));

if (!horz_space) {
    horz_space = 15;
}
if (!duration) {
    duration = 1000;
}
if (interact_mode != 'interactive') {
    interact_mode = 'auto';
}
if (interact_mode == 'auto') {
    time_bar_duration = duration;
}
if (font_size) {
    d3.select('#body')
        .style('font-size', font_size + 'px');
}
if (!max_beam_age) {
    max_beam_age = null;
}

/*
 * Entry point of the whole vis.
 */
function dovis(div, app) {
    var iterations = null,
        T = null,
        root = null,
        time_bar_data = null,
        time_bar = null,
        node_counter = 0,
        tree = null,
        tree_svg = null,
        tree_g = null,
        // stop after the first step (t=0, 'collapse'; just shows prime text)
        stop_t = 0,
        stop_mode = 'expand',
        data = div.data()[0],
        ivocab = data['ivocab'],
        end_token = data['end_token'],
        expanded = [],
        finished = [],
        num_beams_per_group = data['num_beams_per_group'],
        num_finished_per_group = {},
        vis_div = div.append("div")
                    .attr("class", "vismain"),
        beam_div = div.append("div")
                    .attr("class", "beams"),
        invisible_div = div.append("div")
                    .attr("id", "test");

    // TODO: directly select body?
    d3.select("body")
        .on("keydown", function() {
            // don't scroll with arrow keys
            switch(d3.event.keyCode) {
                // Arrow keys
                case 37:
                case 38:
                case 39:
                case 40:
                    d3.event.preventDefault();
                    break;
                default:
                    break;
            }
            // right arrow
            if (d3.event.keyCode == 39 && interact_mode == 'interactive') {
                if (stop_mode == 'expand' && stop_t+1 < time_bar_data.length) {
                    stop_mode = 'collapse';
                    stop_t += 1;
                } else if (stop_mode == 'collapse') {
                    stop_mode = 'expand';
                }
                update_time_bar();
            }
        });

    var final_probs = data['final_probs'];
    iterations = data['iterations'];
    T = data['T'];
    // initialize the tree
    root = {
        name: "root",
        x0: height / 2,
        kept_t: 0,
    };
    if (app === 'char-rnn') {
        root.display = data['prime_text'];
    } else if (app === 'neuraltalk2') {
        root.img_url = data['img_url']
        if (data['prime_text'] !== '') {
            root.prime_text = data['prime_text'];
        }
    }
    var root_hoffset = get_node_dim(root).width;
    root.y0 = root_hoffset;
    // false node (not returned by tree.nodes(root)), but required
    // for the start of the root node transition
    root.parent = {x0: root.x0, y0: root.y0, kept_t: root.kept_t};

    // main vis
    tree_svg = vis_div.append("svg")
            .attr("class", "tree_container")
            .attr("id", "tree_container_0")
            // resize svg so it takes up the whole screen except margins
            .attr("width", (iterations.length+1) * horz_space + root_hoffset + margin.left) //width + margin.left)
            .attr("height", height + margin.top + margin.bottom);
    tree_g = tree_svg.append("g")
            .attr("transform", "translate(" + margin.left + "," + margin.top + ")");
    tree = d3.layout.tree()
        .size([height, width]);
    tree_g.append("foreignObject")
        .html('<button class="button button-outline" id="resetButton">reset</a>');

    // time bar
    var time_bar_svg = vis_div.append("svg")
                .attr("class", "time_bar_container")
                .attr("width", tree_svg.attr("width"))
                .attr("height", time_bar_height);
    time_bar = time_bar_svg.append("g")
            .attr("transform", "translate(" + time_bar_left_margin + "," + 0 + ")");

    show_beams(data.final_beams, data.final_logprobs, data.final_divscores, beam_div, num_beams_per_group);

    // initialize the time bar
    time_bar_svg.append("text")
        .attr("class", "axis_title")
        .attr("transform", "translate(" + iterations.length * horz_space / 2 + "," + 100 + ")")
        .text("Time");
    time_bar_data = iterations.map(function(_, i) { return { i: i }; });
    time_bar_data.push({i: time_bar_data.length});
    init_time_bar();

    // start drawing things
    update_time_bar();
    update(0, 'collapse');

/*
 * Draw time bar according to `time_bar_data`.
 */
function update_time_bar() {
    var tbd = time_bar_data,
        node = time_bar.selectAll("g.time_node")
                .data(time_bar_data);

    var nodeEnter = node.enter().append("g")
        .attr("class", "time_node")
        .attr("transform", function(d) { return "translate(" + d.x + "," + d.y + ")"; });
    nodeEnter.append("circle");
    nodeEnter.append("text")
      .attr("y", "2em")
      .attr("x", "-0.7em")
      .text(function(d) { return d.t; });

    node.select("circle").transition()
        .duration(time_bar_duration)
        .attr("r", function(d) {
            if (d.t == stop_t && stop_mode == 'collapse') {
                return 7;
            } else {
                return 3;
            }
        })
        .attr("stroke", function(d) { return d.t <= stop_t ? highlight_time_color : default_time_color; });

    var links = tbd.slice(0, tbd.length-1)
                    .map(function(_, di) {
                        return {source: tbd[di], target: tbd[di+1]};
                    }),
        link = time_bar.selectAll("path.time_link")
            .data(links);

    var linkEnter = link.enter().insert("path", "g")
          .attr("class", "time_link")
          .attr("d", function(d) {
            return line([d.source, d.target]);
          })

    link.transition()
        .duration(time_bar_duration)
        .attr("stroke", function(d) { return d.target.t <= stop_t ? highlight_time_color : default_time_color; });
}

/*
 * One step at a time, update the internal tree for the current
 * step and then draw it.
 *
 * t: Move the vis state to this time
 * step: Take this step, either 'expand' current beams with
 *       new candidates or 'collapse' candidates into kept beams.
 */
function update(t, recurse) {
    // update time bar and wait until stop_t and stop_mode allow progress
    //console.log('begin time ' + t + ' ' + recurse);
    update_time_bar();
    var wait = (t >= stop_t) && (stop_mode == recurse);
    if (wait) {
        window.setTimeout(update, 100, t, recurse);
        return;
    }

    var data = update_tree_data(t, recurse),
        nodes = data[0],
        links = data[1];

    var node_update = draw_main_vis(t, nodes, links);

    /*
     * Wait for each transition to finish then go to the next step.
     */

    var nfinished = nodes.length;
    var proceed = function(d) {
        nfinished -= 1;
        if (nfinished <= 0) {
          if (recurse == 'expand') {
            update(t+1, 'collapse');
          }
          else if (recurse == 'collapse') {
            update(t, 'expand');
          }
        }
    };
    node_update.each("end", proceed);
}

/*
 * Helpers
 */

function init_time_bar() {
    time_bar_data.forEach(function(d, di) {
        d.x = root_hoffset + di * horz_space;
        d.y = time_bar_height / 3;
        d.t = di;
    });
}

/*
 * Internal vis tree helpers
 */

function update_tree_data(t, recurse) {
    if (recurse == 'expand') {
        expand_candidates(t);
        if (interact_mode == 'auto') {
            stop_t = t+1;
            stop_mode = 'expand';
        }
    }
    else if (recurse == 'collapse') {
        collapse_candidates(t);
        if (interact_mode == 'auto' && stop_t < iterations.length) {
            stop_t = t+1;
            stop_mode = 'collapse';
        }
    }

    // compute node positions
    var nodes = tree.nodes(root);
    nodes.forEach(function(d) {
        d.y = root.y0 + d.depth * horz_space;
        // The if the beam staggered first finishes then its
        // kept_t isn't updated while the others finish.
        if (d.local_t == T && recurse == 'collapse') {
            set_path_kept_t(d, t);
        }
        // prune old beams
        if (max_beam_age && d.children && recurse == 'collapse') {
            d.children = d.children.filter(function(child) {
                return child.kept_t >= t - max_beam_age;
            });
        }
    });
    // TODO: Avoid having to re-layout the nodes. The first layout is needed
    // only because I need to get a list of nodes... this would probably be
    // slightly more efficient if I implemented the tree traversal myself.
    // I think d3's layout takes O(N) time so, this isn't too expensive.
    nodes = tree.nodes(root);
    nodes.forEach(function(d) {
        d.y = root.y0 + d.depth * horz_space;
        // The if the beam staggered first finishes then its
        // kept_t isn't updated while the others finish.
        if (d.local_t == T && recurse == 'collapse') {
            set_path_kept_t(d, t);
        }
    });
    var links = tree.links(nodes);
    return [nodes, links];
}

function expand_candidates(t) {
    expanded = [];
    iterations[t].forEach(function(candidate) {
        var node;
        if (candidate.local_t == 1) {
            node = root;
        } else {
            node = iterations[candidate.t_prev-1][candidate.cid_prev-1];
        }
        if (node.c == end_token) {
            return;
        }
        if (!node.hasOwnProperty('children')) {
            node.children = [];
        }
        node.children.push(candidate);
        expanded.push(node);
    });
    expanded = expanded.filter(onlyUnique);
}

function collapse_candidates(t) {
    expanded.forEach(function(beam) {
        beam.children = beam.children.filter(function(child) {
            if (child.kept && !child.hasOwnProperty('kept_t')) {
                child.first_kept_t = t;
            }
            return child.kept;
        });
        beam.children.forEach(function(child) {
            var group_ix = child.divm - 1;
            if (!num_finished_per_group.hasOwnProperty(group_ix)) {
                num_finished_per_group[group_ix] = 0;
            }
            if (child.c == end_token && child.kept_forever) {
                finished.push(child);
                num_finished_per_group[group_ix] += 1;
            }
            if (num_finished_per_group[group_ix] < num_beams_per_group[group_ix]) {
                set_path_kept_t(child, child.first_kept_t);
            }
        });
    });
    finished.forEach(function(beam) {
        set_path_kept_t(beam, t);
    });
}

function on_path(node, t) {
    return node.kept_t >= t;
}

/*
 * Indicate that each node from child to root was kept at time t or greater.
 *
 * The `kept_t` attribute of each ancestor of child is set to
 * indicate the ancestor is used in a beam that was kept at time `kept_t`.
 */
function set_path_kept_t(child, t) {
    var node = child;
    while (node.parent) {
        if (t >= node.kept_t || !node.hasOwnProperty('kept_t')) {
            node.kept_t = t;
        }
        node = node.parent;
    }
}

/*
 * Display helpers
 */

function draw_main_vis(t, nodes, links) {
    // bind nodes (data) to svg elements
    var node = tree_g.selectAll("g.node")
        .data(nodes, function(d) { return d.id || (d.id = ++node_counter); });

    // create new nodes starting at their parents
    var nodeEnter = node.enter().append("g")
        .attr("class", "node")
        .attr("transform", function(d) { return "translate(" + d.parent.y0 + "," + d.parent.x0 + ")"; });
    nodeEnter.each(display_node)
        .style("fill-opacity", 1e-6);

    // transition all nodes to final destination
    var nodeUpdate = node.transition()
        .duration(duration)
        .attr("transform", function(d) { return "translate(" + d.y + "," + d.x + ")"; });
    // TODO: fill-opacity doesn't work with foreign objects
    nodeUpdate.select("text")
        .style("fill-opacity", function(d) {
            return on_path(d, t) ? 1 : 0.3;
        });

    // remove exiting nodes
    var nodeExit = node.exit().transition()
        .duration(duration)
        .remove();
    nodeExit.select("text")
        .style("fill-opacity", 1e-6);

    // bind links to svg paths
    var link = tree_g.selectAll("path.link")
        .data(links, function(d) { return d.target.id; });

    // enter new links at their sources
    link.enter().insert("path", "g")
        .attr("class", "link")
        .attr("d", function(d) {
            var o = {x: d.source.x0, y: d.source.y0};
            return diagonal({source: o, target: o});
        });

    // transition links to new position
    link.transition()
        .duration(duration)
        .attr("d", diagonal)
        .style("stroke-opacity", function(d) {
            return on_path(d.target, t) ? 1 : 0.3;
        })
        .style("stroke", function(d) {
            return on_path(d.target, t) ?
                        d3.lab(group_colors(d.target.divm)).brighter().brighter().toString() :
                        default_link_color;
        });

    // transition exiting links to their source
    var linkExit = link.exit().transition()
        .duration(duration)
        .attr("d", function(d) {
            return diagonal({
                source: d.source,
                target: d.target,
            });
        })
        .style("stroke-opacity", 0)
        .remove();

    // cached the starting point of the next transition
    nodes.forEach(function(node) {
        node.x0 = node.x;
        node.y0 = node.y;
    });
    return nodeUpdate;
}

function node_text(node) {
    if (node.c) {
        var c = ivocab[node.c - 1];
        if (c == " ") {
            return "' '";
        } else {
            if (special_chars) {
                if (c == "\r") {
                    return "\\r";
                } else if (c == "\n") {
                    return "\\n";
                } else if (node.c == end_token) {
                    return "<end>";
                }
            }
            return c;
        }
    } else if (node.display) {
        return node.display;
    }
}

/*
 * Given a node in some svg context, draw the node in that context.
 */
function display_node(node) {
    if (node.c || node.display) {
        d3.select(this).append("text")
            .text(node_text)
            .attr("text-anchor", function(d) { return (d == root) ? "end" : "start"; });
    } else if (node.img_url) {
        var me = d3.select(this);
        //var fobj = me.append("foreignObject");
        var img = me.append("image")
            .attr("id", "internal" + node.id)
            .attr("height", "100%")
            .on("load", function(d) {
                var img = new Image();
                img.src = d.img_url;
                var scale = img_width / img.width;
                var height = scale * img.height;
                d3.select(this)
                    .attr("height", height + "px")
                    .attr("y", -(height/2) + "px");
            })
            .attr("xlink:href", node.img_url)
            .attr("width", img_width + "px")
            .attr("x", (-root_hoffset) + "px");
        if (node.prime_text) {
            var ptxt = me.append("text")
                        .text(node.prime_text)
                        .attr("text-anchor", "start") //function(d) { return (d == root) ? "end" : "start"; })
                        .attr("x", (-root_hoffset + img_width + img_prime_text_offset) + "px");
        }
    }
}

// TODO: relies on dovis() being called first to create invisible_div
function get_node_dim(node) {
    if (node.c || node.display) {
        var invisible_div = d3.select("#test");
        invisible_div.html(node_text(node));
        return {
            width: (parseFloat(invisible_div.style("width")) + 1),
            height: (parseFloat(invisible_div.style("height")) + 1),
        };
    } else if (node.img_url) {
        if (node.prime_text) {
            var invisible_div = d3.select("#test");
            invisible_div.html(node.prime_text);
            return { width: img_width + parseFloat(invisible_div.style("width")) + img_prime_text_offset };
        } else {
            return { width: img_width };
        }
    } else {
        console.log("width error still exists");
    }
}

/* Show the final beams from torch. */
function show_beams(beams, logprobs, divscores, beam_div, num_beams_per_group) {
    // beam ix -> group ix (1 based, like divm in torch code)
    var group_ixs = [],
        beam_ix = 0;
    num_beams_per_group.forEach(function(num_in_group, group_ix) {
        for(var i = 0; i < num_in_group; i++) {
            group_ixs[beam_ix] = group_ix+1;
            beam_ix += 1;
        }
    });
    beam_div.selectAll("p")
        .data(beams)
      .enter()
        .append("p")
        .text(function(d, di) {
            var result = d;
            if (logprobs) {
                result = result + "  (log probability: " + logprobs[di].toFixed(3) + ")";
            }
            if (divscores) {
                result = result + "  (diversity augmented score: " + divscores[di].toFixed(3) + ")";
            }
            return result;
        })
        .style("color", function(d, di) {
            return d3.lab(group_colors(group_ixs[di])).toString();
        });
}
}

// getters and setters
dovis.width = function(x) {
    if (!arguments.length) return width;
    width = x - margin.right - margin.left;
    return dovis;
};

dovis.height = function(x) {
    if (!arguments.length) return height;
    height = x - margin.top - margin.bottom;
    return dovis;
};

return dovis;

}
})();

function getParameterByName(name, url) {
    if (!url) url = window.location.href;
    name = name.replace(/[\[\]]/g, "\\$&");
    var regex = new RegExp("[?&]" + name + "(=([^&#]*)|&|#|$)"),
        results = regex.exec(url);
    if (!results) return null;
    if (!results[2]) return '';
    return decodeURIComponent(results[2].replace(/\+/g, " "));
}

function onlyUnique(value, index, self) {
    return self.indexOf(value) === index;
}
