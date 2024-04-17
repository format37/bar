import pandas as pd
import plotly.express as px
import plotly.graph_objects as go
import pandas as pd
import random
import seaborn as sns
import colorsys
import matplotlib.pyplot as plt
import plotly.graph_objects as go
import time


class Fork:
    def __init__(self, df):
        self.time = 0
        self.e_amount = 0
        self.m_amount = 0
        self.df = pd.DataFrame(df)
        self.unit = ''
        self.bt = 0
        self.branches = []
        self.name = ''
        self.parent_fork = None
        self.keep = False


def fill_branches(parent_fork, time_limit, candidates):
    # Print the current state
    # print('> unit:', parent_fork.unit)
    # print('> time:', parent_fork.time)
    # print('> e_amount:', parent_fork.e_amount)
    # print('> m_amount:', parent_fork.m_amount)
    e_prod = (parent_fork.df.e_prod * parent_fork.df['cnt']).sum()
    m_prod = (parent_fork.df.m_prod * parent_fork.df['cnt']).sum()
    # Print debug e_prod, m_prod
    # print(f'> e_prod: {e_prod}')
    # print(f'> m_prod: {m_prod}')
    # print(f"fill_branches {int(parent_fork.time)}")
    
    for candidate in candidates:
        row = parent_fork.df[parent_fork.df['unit'] == candidate]
        e_cost = row['e_cost'].values[0]
        m_cost = row['m_cost'].values[0]
        bp_sum = (parent_fork.df.bp*parent_fork.df['cnt']).sum()
        bt = row['ubt'].values[0]*100/bp_sum
        
        if e_cost > parent_fork.e_amount + e_prod * bt \
            or m_cost > parent_fork.m_amount + m_prod * bt:
            # print('not enough resources:', candidate, e_cost, m_cost)
            continue
        
        # print('candidate:', candidate, e_cost, m_cost)
        fork = Fork(parent_fork.df.copy())  # Create a new copy of the DataFrame
        fork.parent_fork = parent_fork
        fork.unit = candidate
        fork.bt = bt
        fork.time = parent_fork.time + fork.bt
        # Calculate e_cap and m_cap
        e_cap = (fork.df.e_cap*fork.df['cnt']).sum()
        m_cap = (fork.df.m_cap*fork.df['cnt']).sum()
        fork.e_amount = parent_fork.e_amount - e_cost + e_prod * bt
        fork.m_amount = parent_fork.m_amount - m_cost + m_prod * bt
        """if fork.e_amount > e_cap:
            fork.e_amount = e_cap
        if fork.m_amount > m_cap:
            fork.m_amount = m_cap"""
        if fork.e_amount > e_cap or fork.m_amount > m_cap:
            # Don't need forks that exceed the cap
            continue
        
        # Update the count for the specific row
        row_index = fork.df.index[fork.df['unit'] == candidate].tolist()[0]
        # print(f"<# {parent_fork.df.loc[parent_fork.df['unit'] == candidate, 'm_cost']}")
        fork.df.iloc[row_index, fork.df.columns.get_loc('cnt')] += 1

        fork.name = parent_fork.name + '-' + candidate
        # print(f"< name: {fork.name}, count: {fork.df.loc[fork.df['unit'] == candidate, 'cnt'].values[0]}")
        # Print name, current e_prod, parent e_prod
        e_prod = (fork.df.e_prod*fork.df['cnt']).sum()
        parent_e_prod = (parent_fork.df.e_prod*parent_fork.df['cnt']).sum()
        # print(f"< name: {fork.name}, {parent_e_prod} >> {e_prod}")
        if fork.time > time_limit:
            # print('time is over:', fork.time)
            return
        fill_branches(fork, time_limit, candidates)
        parent_fork.branches.append(fork)


# calculate the overall forks count
def count_forks(fork, tops, forks):
    count = 1
    for branch in fork.branches:
        forks.append(branch)
        cf, forks, tops = count_forks(branch, tops, forks)
        count += cf
        # if (branch.df.m_prod*branch.df['cnt']).sum() > 7.4:
        e_prod = (branch.df.e_prod*branch.df['cnt']).sum()
        m_prod = (branch.df.m_prod*branch.df['cnt']).sum()
        bp = (branch.df.bp*branch.df['cnt']).sum()
        if e_prod >= tops['e_prod']['value']:
            tops['e_prod']['value'] = e_prod
            tops['e_prod']['name'] = branch.name
            if branch.time <= tops['e_prod']['time']:
                tops['e_prod']['time'] = branch.time
        if m_prod >= tops['m_prod']['value']:
            tops['m_prod']['value'] = m_prod
            tops['m_prod']['name'] = branch.name
            if branch.time <= tops['m_prod']['time']:
                tops['m_prod']['time'] = branch.time
        if branch.e_amount >= tops['e_amount']['value']:
            tops['e_amount']['value'] = branch.e_amount
            tops['e_amount']['name'] = branch.name
            if branch.time <= tops['e_amount']['time']:
                tops['e_amount']['time'] = branch.time
        if branch.m_amount >= tops['m_amount']['value']:
            tops['m_amount']['value'] = branch.m_amount
            tops['m_amount']['name'] = branch.name
            if branch.time <= tops['m_amount']['time']:
                tops['m_amount']['time'] = branch.time
        if bp >= tops['bp']['value']:
            tops['bp']['value'] = bp
            tops['bp']['name'] = branch.name
            if branch.time <= tops['bp']['time']:
                tops['bp']['time'] = branch.time
    return count, forks, tops

def plot_recursive_forks(fork, plotted_forks, fig, param):
    for branch in fork.branches:
        skip = False
        # Iterate in plotted forks
        for plotted_fork in plotted_forks:
            if branch.name in plotted_fork: #  or plotted_fork in branch.name:
                skip = True
                break
        if skip:
            continue
        
        plotted_forks.add(branch.name)
        plotted_forks, fig = plot_recursive_forks(branch, plotted_forks, fig, param)
        
        parent_fork = branch.parent_fork
        
        x = [parent_fork.time]
        x.append(branch.time)
        
        if param in parent_fork.df.columns:
            y = [(parent_fork.df[param] * parent_fork.df['cnt']).sum()]
            prod = (branch.df[param] * branch.df['cnt']).sum()
            y.append(prod)
        elif param == 'e_amount':
            y = [parent_fork.e_amount]
            y.append(branch.e_amount)
        elif param == 'm_amount':
            y = [parent_fork.m_amount]
            y.append(branch.m_amount)
        else:
            print('Invalid parameter')
            exit()

        trace = go.Scatter(
            x=x,
            y=y,
            mode='lines+markers',
            name=f"{branch.name}",
            marker=dict(symbol='circle'),
            line=dict(width=2),
            hovertemplate='%{text}<extra></extra>',
            text=[f"{branch.name}" for _ in range(len(x))]
        )
        fig.add_trace(trace)

    return plotted_forks, fig


def plot_forks(fork, fig, param):
    print(f"Plotting {param}")
    plotted_forks = set()  # Set to keep track of plotted lines
    
    plot_recursive_forks(fork, plotted_forks, fig, param)

    # Update layout
    fig.update_layout(
        title='Evolution Lines',
        xaxis_title='Time',
        yaxis_title=param,
        template="plotly_white"
    )

    # Generate filename
    filename = f"evolution_lines_{param}.html"

    # Save the plot as an HTML file
    fig.write_html(filename)

    # Show the plot
    # fig.show()

def copy_filtered_branch(fork, filtered_branch):
    if fork.keep:
        new_fork = Fork(fork.df.copy())
        new_fork.time = fork.time
        new_fork.e_amount = fork.e_amount
        new_fork.m_amount = fork.m_amount
        new_fork.unit = fork.unit
        new_fork.bt = fork.bt
        new_fork.name = fork.name
        new_fork.keep = True

        filtered_branch.branches.append(new_fork)

        if fork.parent_fork is not None:
            parent_fork = next((f for f in filtered_branch.branches if f.name == fork.parent_fork.name), None)
            if parent_fork is None:
                parent_fork = copy_filtered_branch(fork.parent_fork, filtered_branch)
            new_fork.parent_fork = parent_fork

        return new_fork

def set_keep_recursive(fork):
    fork.keep = True
    if fork.parent_fork is not None:
        set_keep_recursive(fork.parent_fork)

def filter_forks(forks, tops, initial_branch):
    filtered_branch = Fork(initial_branch.df.copy())
    filtered_branch.time = initial_branch.time
    filtered_branch.e_amount = initial_branch.e_amount
    filtered_branch.m_amount = initial_branch.m_amount
    filtered_branch.unit = initial_branch.unit
    filtered_branch.bt = initial_branch.bt
    filtered_branch.name = initial_branch.name

    for category in tops:
        top_fork_name = tops[category]['name']
        for fork in forks:
            if fork.name == top_fork_name:
                set_keep_recursive(fork)

    for fork in forks:
        if fork.keep:
            copy_filtered_branch(fork, filtered_branch)

    return filtered_branch


def main():
    time_limit = 120
    initial_state = {
            'unit': ['game', 'com', 'mex', 'solar', 'wind','con', 'ec', 'nano', 'solar_adv', 'es', 'ms'],
            'cnt': [1, 1, 3, 2, 3, 1, 0, 0, 0, 0, 0]
        }
    candidates = ['solar','wind','solar_adv','ec', 'es', 'ms', 'nano']

    time_start = time.time()

    params = pd.read_csv('data.csv')

    df = pd.DataFrame(initial_state)

    # Merge the two dataframes based on the 'entity' and 'name' columns
    merged_df = pd.merge(df, params, left_on='unit', right_on='unit', how='left')

    branch = Fork(merged_df)
    branch.time = 92
    branch.df = merged_df
    branch.e_amount = 78
    branch.m_amount = 255
    branch.unit = 'con'
    branch.name = 'con'
    branch.bt = merged_df[merged_df['unit'] == 'con']['ubt'].values[0]/300 # By com

    print('Generating forks..')
    fill_branches(branch, time_limit, candidates)

    forks = []
    tops = {
        'e_prod': {
            "value": 0,
            "name": "",
            "time": time_limit*2
        },
        'm_prod': {
            "value": 0,
            "name": "",
            "time": time_limit*2
        },
        'e_amount': {
            "value": 0,
            "name": "",
            "time": time_limit*2
        },
        'm_amount': {
            "value": 0,
            "name": "",
            "time": time_limit*2
        },
        'bp': {
            "value": 0,
            "name": "",
            "time": time_limit*2
        }
    }
    count_of_forks, forks, tops = count_forks(branch, tops, forks)
    print('total forks:', count_of_forks)
    print('tops:', tops)

    branch = filter_forks(forks, tops, branch)
    print('Filtered forks count:', len(branch.branches))

    if True:

        # Plot the evolution line
        fig = go.Figure()
        plot_forks(branch, fig, 'e_prod')
        
        fig = go.Figure()
        plot_forks(branch, fig, 'm_prod')

        fig = go.Figure()
        plot_forks(branch, fig, 'e_amount')

        fig = go.Figure()
        plot_forks(branch, fig, 'm_amount')

        fig = go.Figure()
        plot_forks(branch, fig, 'bp')

    time_end = time.time()

    print(f"Execution time: {time_end - time_start}")

    print('done')


if __name__ == '__main__':
    main()
