from __future__ import annotations
from typing import TYPE_CHECKING
import time

import click
if TYPE_CHECKING:
    from click._termui_impl import ProgressBar


from cyndilib.router import Router, RoutingMatrix



def format_matrix(matrix: RoutingMatrix|None) -> str:
    """Format the routing matrix for display in the progress bar

    Each :class:`~cyndilib.router.Router` will be displayed in the format
    ``dest -> source - N connections`` with text styled to indicate the
    status of the router.
    """

    def format_router(router: Router) -> str:
        is_active = router.is_active
        num_connections = router.get_num_connections()

        sep = click.style(' -> ', fg='white', bold=True)
        dest_src = sep.join([
            click.style(f'{router.dest}', fg='cyan', bold=is_active),
            click.style(f'{router.source}', fg='magenta', bold=is_active)
        ])
        c_str = click.style(f'{num_connections} connections', fg='white', dim=True)
        return f'{dest_src} - {c_str}'

    if matrix is None:
        return ''
    routers = [format_router(router) for router in matrix]
    sep = click.style(' | ', fg='white', bold=True)
    prefix = click.style('Routing Matrix:', fg='yellow', bold=True)
    return sep.join([prefix] + routers)



def main(routing_table: dict[str, str | None], duration: float|None):
    """Main function to run the routing matrix with the specified routing table
    and duration.
    """
    sleep_interval = 0.1

    # Calculate progress bar parameters using milliseconds
    # since it requires integer values.
    duration_ms = int(duration * 1000) if duration is not None else None
    sleep_interval_ms = int(sleep_interval * 1000)
    n_steps = duration_ms // sleep_interval_ms if duration_ms is not None else 1


    click.echo('Building matrix with routing table:')
    for dest, source in routing_table.items():
        click.echo(f"  '{dest}' -> '{source}'")
    click.echo('')

    # Build the routing matrix and set the routing table
    matrix = RoutingMatrix()
    matrix.set_routing_table(routing_table)


    if duration is not None:
        click.echo(f"Running for {duration} seconds...")
    else:
        click.echo("Running indefinitely (press Ctrl+C to stop)...")


    # Open the routing matrix and display the routing status in a progress bar
    # until the specified duration has elapsed or the user interrupts with Ctrl+C
    with matrix:

        # The progress bar is only used to display the routing status on the
        # terminal without filling it with log messages.
        bar: ProgressBar[RoutingMatrix] = click.progressbar(
            length=n_steps,
            show_eta=False,
            show_percent=False,
            bar_template='%(label)s    %(info)s',
            item_show_func=format_matrix,
        )

        with bar:
            start_time = time.time()
            i = 0
            while True:
                try:
                    time.sleep(sleep_interval)
                    elapsed = time.time() - start_time
                    bar.label = time.strftime("%H:%M:%S", time.gmtime(elapsed))
                    bar.update(1, current_item=matrix)
                    if duration_ms is not None:
                        i += 1
                        if i > n_steps:
                            break
                except KeyboardInterrupt:
                    break
    click.echo("Routing matrix closed.")



@click.command()
@click.option(
    '--duration',
    default=None,
    show_default=True,
    type=float,
    help='Time in seconds to run. If not specified, run indefinitely until interrupted.'
)
@click.option(
    '--route', '-r',
    multiple=True,
    help='Routing in the format "dest:source". Can be specified multiple times.'
)
def cli(duration: float|None, route: list[str]):
    """Create a routing matrix with the specified routing table and run it for
    the specified duration.

    Each route specified ('-r' or '--route') should be in the format "dest:source",
    where "dest" is the name of the router to create
    and "source" is the full name of the |NDI| source to connect to that router.

    If "source" is "None", the router will be created with no source,
    effectively a blank route.

    \b
    Example usage:
    python router.py -r "MyDest:SOURCEHOSTNAME (SourceStreamName)" -r "MyOtherDest:None" --duration 60

    """
    routing_table: dict[str, str | None] = {}

    # Parse the routing table from the command line arguments
    for r in route:
        try:
            dest, source = r.split(':', 1)
            dest, source = dest.strip(), source.strip()
            if source == 'None':
                source = None
            routing_table[dest] = source
        except ValueError:
            print(f"Invalid route format: {r}. Expected format is 'dest:source'.")
            return

    # Run the main function with the parsed routing table and duration
    main(routing_table, duration)


if __name__ == '__main__':
    cli()
