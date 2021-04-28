import { useContext } from 'react';
import { List, ListItem, Divider, Box } from '@material-ui/core';
import { makeStyles } from '@material-ui/core/styles';
import { ClassNameMap } from '@material-ui/styles';
import Panel from './Panel';
import PeriodicFetch from '../lib/fetchers/periodicFetch';
import { HeaderText, BodyText } from './Text';
import { BLUE, GREY, HOVER, DIVIDER } from '../lib/consts/DEFAULT_THEME';
import { AnvilContext } from './AnvilContext';

const useStyles = makeStyles(() => ({
  root: {
    width: '100%',
    overflow: 'auto',
    height: '100%',
  },
  divider: {
    background: DIVIDER,
  },
  button: {
    '&:hover': {
      backgroundColor: HOVER,
    },
    paddingLeft: 0,
  },
  noPaddingLeft: {
    paddingLeft: 0,
  },
  decorator: {
    width: '20px',
    height: '100%',
    borderRadius: 2,
  },
  started: {
    backgroundColor: BLUE,
  },
  stopped: {
    backgroundColor: GREY,
  },
}));

const selectDecorator = (
  state: string,
): keyof ClassNameMap<'started' | 'stopped'> => {
  switch (state) {
    case 'Started':
      return 'started';
    case 'Stopped':
      return 'stopped';
    default:
      return 'stopped';
  }
};

const Servers = ({ anvil }: { anvil: AnvilListItem[] }): JSX.Element => {
  const { uuid } = useContext(AnvilContext);
  const classes = useStyles();

  const { data } = PeriodicFetch<AnvilServers>(
    `${process.env.NEXT_PUBLIC_API_URL}/anvils/get_servers?anvil_uuid=`,
    uuid,
  );
  return (
    <Panel>
      <HeaderText text="Servers" />
      <List
        component="nav"
        className={classes.root}
        aria-label="mailbox folders"
      >
        {data &&
          data.servers.map((server: AnvilServer) => {
            return (
              <>
                <ListItem
                  button
                  className={classes.button}
                  key={server.server_uuid}
                >
                  <Box display="flex" flexDirection="row" width="100%">
                    <Box p={1} className={classes.noPaddingLeft}>
                      <div
                        className={`${classes.decorator} ${
                          classes[selectDecorator(server.server_state)]
                        }`}
                      />
                    </Box>
                    <Box p={1} flexGrow={1} className={classes.noPaddingLeft}>
                      <BodyText text={server.server_name} />
                      <BodyText text={server.server_state} />
                    </Box>
                    {server.server_state === 'Started' &&
                      anvil[
                        anvil.findIndex((a) => a.anvil_uuid === uuid)
                      ].nodes.map(
                        (
                          node: AnvilListItemNode,
                          index: number,
                        ): JSX.Element => (
                          <Box p={1} key={node.node_uuid}>
                            <BodyText
                              text={node.node_name}
                              selected={server.server_host_index === index}
                            />
                          </Box>
                        ),
                      )}
                  </Box>
                </ListItem>
                <Divider className={classes.divider} />
              </>
            );
          })}
      </List>
    </Panel>
  );
};

export default Servers;